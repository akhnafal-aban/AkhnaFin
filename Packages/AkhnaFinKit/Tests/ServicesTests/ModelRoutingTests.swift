import Testing
import Foundation
import ServiceInterfaces
@testable import Services

/// URLProtocol khusus suite ini (handler statis per suite — hindari race antar
/// suite paralel, gotcha sesi 02).
final class RoutingMockURLProtocol: URLProtocol {
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

@Suite("Model routing per-peran (PLAN-007)", .serialized)
struct ModelRoutingTests {
    private let result = """
    {"amount":20000,"type":"expense","days_ago":0,"merchant":"Kantin","note":"bakso","category_name":"Main Food","subcategory_name":""}
    """

    private func makeOpenRouterParser(store: any ModelPreferenceStoring) -> OpenRouterParser {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RoutingMockURLProtocol.self]
        let keyStore = MockAPIKeyStore(initialKey: "sk-or-test")
        return OpenRouterParser(
            client: OpenRouterClient(keyStore: keyStore, session: URLSession(configuration: config)),
            keyStore: keyStore,
            categoryNames: ["Main Food"], subcategoryNames: [],
            preferenceStore: store
        )
    }

    @Test("ModelPreference default = Gemma utk kedua peran; roundtrip Codable")
    func preferenceDefaults() throws {
        let standard = ModelPreference.standard
        guard case .openRouter(let slug, let structured, _) = standard.text else {
            Issue.record("default teks harus OpenRouter"); return
        }
        #expect(slug == "google/gemma-4-26b-a4b-it:free")
        #expect(structured)
        let encoded = try JSONEncoder().encode(standard)
        #expect(try JSONDecoder().decode(ModelPreference.self, from: encoded) == standard)
    }

    @Test("ModelPreferenceStore: save/load via UserDefaults suite terpisah")
    func storeRoundtrip() {
        let defaults = UserDefaults(suiteName: "test.modelpref.\(UUID().uuidString)")!
        let store = ModelPreferenceStore(defaults: defaults)
        #expect(store.load() == .standard)
        var preference = ModelPreference.standard
        preference.text = .appleLocal
        store.save(preference)
        #expect(store.load().text == .appleLocal)
    }

    @Test("OpenRouterParser memakai slug dari preferensi per peran (teks vs gambar beda model)")
    func slugPerRole() async throws {
        nonisolated(unsafe) var models: [String] = []
        RoutingMockURLProtocol.handler = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            models.append(body["model"] as! String)
            let json = ["choices": [["message": ["content": self.result]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let store = MockModelPreferenceStore(initial: ModelPreference(
            text: .openRouter(slug: "model/teks", supportsStructured: true, displayName: "T"),
            image: .openRouter(slug: "model/gambar", supportsStructured: true, displayName: "G")
        ))
        let parser = makeOpenRouterParser(store: store)
        _ = try await parser.parse("beli bakso 20k")
        _ = try await parser.parseReceipt(image: Data([0xFF]))
        #expect(models == ["model/teks", "model/gambar"])
    }

    @Test("Model non-structured → tanpa response_format + JSON dgn fences tetap ter-decode")
    func nonStructuredModelPath() async throws {
        nonisolated(unsafe) var hadResponseFormat = true
        RoutingMockURLProtocol.handler = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            hadResponseFormat = body["response_format"] != nil
            let fenced = "```json\n\(self.result)\n```"
            let json = ["choices": [["message": ["content": fenced]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let store = MockModelPreferenceStore(initial: ModelPreference(
            text: .openRouter(slug: "nvidia/nemotron-x", supportsStructured: false, displayName: "N"),
            image: ModelPreference.standard.image
        ))
        let parser = makeOpenRouterParser(store: store)
        let draft = try await parser.parse("beli bakso 20k")
        #expect(!hadResponseFormat)
        #expect(draft.amount == 20000)
    }

    @Test("RoutingParser: peran teks Apple + peran gambar OpenRouter berjalan independen")
    func mixedEngines() async throws {
        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": self.result]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let store = MockModelPreferenceStore(initial: ModelPreference(
            text: .appleLocal,
            image: ModelPreference.standard.image
        ))
        let routing = RoutingTransactionParser(
            apple: AppleTransactionParser(categoryNames: [], subcategoryNames: []),
            openRouter: makeOpenRouterParser(store: store),
            preferenceStore: store
        )
        // Gambar → OpenRouter (mock) tetap jalan meski teks = Apple.
        let draft = try await routing.parseReceipt(image: Data([0xFF]))
        #expect(draft.amount == 20000)
        // availability mengikuti engine teks (Apple; di host test macOS FM bisa
        // available/tidak — cukup pastikan TIDAK menyentuh jalur OpenRouter
        // no-key, yaitu tidak menyebut Pengaturan/API key).
        if case .unavailable(let reason) = routing.availability {
            #expect(!reason.contains("OpenRouter"))
        }
    }
}
