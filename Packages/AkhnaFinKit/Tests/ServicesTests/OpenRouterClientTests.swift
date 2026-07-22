import Testing
import Foundation
@testable import Services
import ServiceInterfaces

/// URLProtocol mock — tangkap request, balas fixture. Tanpa network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        // httpBody hilang di URLProtocol — baca dari stream.
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            request.httpBody = data
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("OpenRouterClient — transport & error mapping", .serialized)
struct OpenRouterClientTests {
    private func makeClient(key: String? = "sk-or-test") -> OpenRouterClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return OpenRouterClient(
            keyStore: MockAPIKeyStore(initialKey: key),
            session: URLSession(configuration: config)
        )
    }

    private static func success(content: String) -> Data {
        let json = ["choices": [["message": ["content": content]]]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private let schema = #"{"type":"object","properties":{"x":{"type":"string"}},"required":["x"],"additionalProperties":false}"#

    @Test("Auth Bearer + response_format json_schema strict terkirim")
    func requestShape() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            return (200, Self.success(content: #"{"x":"ok"}"#))
        }
        _ = try await makeClient().completeStructured(
            model: "openai/gpt-oss-120b:free",
            messages: [.system("s"), .user([.text("halo")])],
            schemaName: "test",
            schemaJSON: schema
        )
        let request = try #require(captured)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as! [String: Any]
        #expect(body["model"] as? String == "openai/gpt-oss-120b:free")
        let format = body["response_format"] as! [String: Any]
        #expect(format["type"] as? String == "json_schema")
        let schemaObj = format["json_schema"] as! [String: Any]
        #expect(schemaObj["strict"] as? Bool == true)
        #expect((body["provider"] as! [String: Any])["require_parameters"] as? Bool == true)
    }

    @Test("structured:false → tanpa response_format & tanpa provider (routing bebas)")
    func nonStructuredOmitsSchema() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            return (200, Self.success(content: #"{"x":"ok"}"#))
        }
        _ = try await makeClient().completeStructured(
            model: "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free",
            messages: [.user([.text("halo")])],
            schemaName: "test", schemaJSON: schema, structured: false
        )
        let body = try JSONSerialization.jsonObject(with: #require(captured?.httpBody)) as! [String: Any]
        #expect(body["response_format"] == nil)
        #expect(body["provider"] == nil)
    }

    @Test("Gambar diserialisasi sebagai data URL image_url")
    func imagePart() async throws {
        nonisolated(unsafe) var captured: URLRequest?
        MockURLProtocol.handler = { request in
            captured = request
            return (200, Self.success(content: #"{"x":"ok"}"#))
        }
        let imageBytes = Data([0xFF, 0xD8, 0xFF])
        _ = try await makeClient().completeStructured(
            model: "m", messages: [.user([.image(imageBytes)])],
            schemaName: "t", schemaJSON: schema
        )
        let body = try JSONSerialization.jsonObject(with: #require(captured?.httpBody)) as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        let parts = messages[0]["content"] as! [[String: Any]]
        let urlDict = parts[0]["image_url"] as! [String: String]
        #expect(urlDict["url"]?.hasPrefix("data:image/jpeg;base64,") == true)
        #expect(urlDict["url"]?.contains(imageBytes.base64EncodedString()) == true)
    }

    @Test("Content hasil structured output dikembalikan sebagai Data")
    func contentReturned() async throws {
        MockURLProtocol.handler = { _ in (200, Self.success(content: #"{"x":"nilai"}"#)) }
        let data = try await makeClient().completeStructured(
            model: "m", messages: [.user([.text("t")])], schemaName: "t", schemaJSON: schema
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: String]
        #expect(obj["x"] == "nilai")
    }

    @Test("Tanpa key → modelUnavailable tanpa menyentuh network")
    func missingKey() async {
        MockURLProtocol.handler = { _ in
            Issue.record("network tak boleh disentuh")
            return (200, Data())
        }
        await #expect(throws: TransactionParsingError.self) {
            _ = try await makeClient(key: nil).completeStructured(
                model: "m", messages: [], schemaName: "t", schemaJSON: schema
            )
        }
    }

    @Test("401 → key tidak valid; 429 → pesan rate limit")
    func errorMapping() async {
        MockURLProtocol.handler = { _ in (401, Data(#"{"error":{"message":"bad key"}}"#.utf8)) }
        do {
            _ = try await makeClient().completeStructured(
                model: "m", messages: [], schemaName: "t", schemaJSON: schema
            )
            Issue.record("harus melempar")
        } catch let error as TransactionParsingError {
            #expect(error.errorDescription?.contains("tidak valid") == true)
        } catch { Issue.record("tipe error salah") }

        MockURLProtocol.handler = { _ in (429, Data(#"{"error":{"message":"rate limited"}}"#.utf8)) }
        do {
            _ = try await makeClient().completeStructured(
                model: "m", messages: [], schemaName: "t", schemaJSON: schema
            )
            Issue.record("harus melempar")
        } catch let error as TransactionParsingError {
            #expect(error.errorDescription?.contains("Batas gratis") == true)
        } catch { Issue.record("tipe error salah") }
    }
}
