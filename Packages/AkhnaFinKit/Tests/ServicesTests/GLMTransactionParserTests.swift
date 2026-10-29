import Testing
import Foundation
import AkhnaFinCore
import ServiceInterfaces
@testable import Services

final class GLMParserMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
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

@Suite("GLMTransactionParser", .serialized)
struct GLMTransactionParserTests {
    private func chatBody(content: String) -> Data {
        let json = ["choices": [["message": ["content": content]]]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func makeParser(
        key: String? = "wandb_v1-test",
        onRequest: (@Sendable ([String: Any], URLRequest) -> Void)? = nil
    ) -> GLMTransactionParser {
        GLMParserMockURLProtocol.handler = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            onRequest?(body, request)
            return (200, self.chatBody(content: Self.responseJSON))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GLMParserMockURLProtocol.self]
        let keyStore = MockAPIKeyStore(initialKey: key)
        return GLMTransactionParser(
            client: InferenceClient(keyStore: keyStore, session: URLSession(configuration: config)),
            keyStore: keyStore,
            categoryNames: ["Main Food", "Tagihan", "Gaji"],
            subcategoryNames: ["Jajan"]
        )
    }

    private static let responseJSON = """
    {"amount":20000,"type":"expense","days_ago":1,"merchant":"Kantin Kantor","note":"bakso","category_name":"Main Food","subcategory_name":""}
    """

    @Test("availability mengikuti keberadaan key")
    func availabilityFollowsKey() {
        #expect(makeParser(key: nil).availability != .available)
        #expect(makeParser().availability == .available)
    }

    @Test("parse: konten bersih → draft lengkap + rawInput")
    func parseClean() async throws {
        let parser = makeParser()
        let draft = try await parser.parse("beli bakso 20k kemarin di kantin")
        #expect(draft.amount == 20000)
        #expect(draft.type == .expense)
        #expect(draft.merchant == "Kantin Kantor")
        #expect(draft.categoryName == "Main Food")
        #expect(draft.rawInput == "beli bakso 20k kemarin di kantin")
        let calendar = Calendar.current
        #expect(calendar.isDate(draft.date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: .now)!))
    }

    @Test("parse: konten dalam code fence tetap terbaca")
    func parseCodeFence() async throws {
        let parser = makeParser()
        let draft = try await parser.parse("x")
        #expect(draft.amount == 20000)
    }

    @Test("request: model GLM-5.3 + reasoning max + bearer key")
    func requestFormation() async throws {
        nonisolated(unsafe) var seenModel = ""
        nonisolated(unsafe) var seenEffort = ""
        nonisolated(unsafe) var seenAuth = ""
        let parser = makeParser { body, request in
            seenModel = body["model"] as! String
            seenEffort = body["reasoning_effort"] as! String
            seenAuth = request.value(forHTTPHeaderField: "Authorization") ?? ""
        }
        _ = try await parser.parse("kopi 12k")
        #expect(seenModel == "zai-org/GLM-5.3")
        #expect(seenEffort == "max")
        #expect(seenAuth == "Bearer wandb_v1-test")
    }

    @Test("parseReceipt tanpa key: heuristik lokal, tanpa network")
    func receiptFallsBackToHeuristics() async throws {
        nonisolated(unsafe) var networkCalled = false
        let parser = makeParser(key: nil) { _, _ in networkCalled = true }
        let ocr = """
        INDOMARET
        AIR MINERAL 5.000
        ROTI 8.000
        TOTAL 13.000
        """
        let draft = try await parser.parseReceipt(text: ocr)
        #expect(networkCalled == false)
        #expect(draft.amount == 13_000)
        #expect(draft.type == .expense)
    }

    @Test("parseReceipt dengan key: lewat GLM")
    func receiptUsesGLM() async throws {
        let parser = makeParser()
        let draft = try await parser.parseReceipt(text: "TOTAL 13.000")
        #expect(draft.amount == 20000)
        #expect(draft.merchant == "Kantin Kantor")
    }

    @Test("HTTP 401 → modelUnavailable pesan siap-tampil")
    func invalidKey() async {
        GLMParserMockURLProtocol.handler = { _ in
            (401, Data(#"{"error":{"message":"invalid api key"}}"#.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GLMParserMockURLProtocol.self]
        let keyStore = MockAPIKeyStore(initialKey: "salah")
        let parser = GLMTransactionParser(
            client: InferenceClient(keyStore: keyStore, session: URLSession(configuration: config)),
            keyStore: keyStore,
            categoryNames: [],
            subcategoryNames: []
        )
        do {
            _ = try await parser.parse("x")
            Issue.record("harus melempar")
        } catch let error as TransactionParsingError {
            #expect(String(describing: error).contains("modelUnavailable"))
        } catch {
            Issue.record("tipe error salah")
        }
    }

    @Test("decode: mapping edge (type asing → expense, daysAgo negatif → hari ini)")
    func mappingEdgeCases() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 20))!
        let parsed = GLMParsedTransaction(
            amount: -5, type: "belanja", daysAgo: -3,
            merchant: "", note: "", categoryName: "", subcategoryName: ""
        )
        let draft = parsed.draft(rawInput: "raw", now: now, calendar: calendar)
        #expect(draft.amount == 0)
        #expect(draft.type == .expense)
        #expect(calendar.isDate(draft.date, inSameDayAs: now))
    }

    @Test("extractJSON: tolak konten tanpa objek")
    func extractJSONRejectsNonObject() {
        #expect(GLMTransactionParser.extractJSON(from: "maaf, saya tidak paham") == nil)
    }
}