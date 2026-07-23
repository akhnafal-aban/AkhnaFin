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

    @Test("404 no-endpoints → tangga fallback: structured+reasoning → tanpa reasoning → non-structured")
    func noEndpointsFallbackLadder() async throws {
        nonisolated(unsafe) var bodies: [[String: Any]] = []
        RoutingMockURLProtocol.handler = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            bodies.append(body)
            // Dua percobaan pertama ditolak "No endpoints found"; ketiga sukses
            // (content dgn fences — jalur non-structured harus tetap decode).
            if bodies.count < 3 {
                return (404, Data(#"{"error":{"message":"No endpoints found that can handle the requested parameters."}}"#.utf8))
            }
            let fenced = "```json\n\(self.result)\n```"
            let json = ["choices": [["message": ["content": fenced]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        let draft = try await parser.parse("beli bakso 20k")
        #expect(draft.amount == 20000)
        #expect(bodies.count == 3)
        // Attempt 1: structured + reasoning low
        #expect(bodies[0]["response_format"] != nil)
        #expect((bodies[0]["reasoning"] as? [String: String])?["effort"] == "low")
        // Attempt 2: structured tanpa reasoning
        #expect(bodies[1]["response_format"] != nil)
        #expect(bodies[1]["reasoning"] == nil)
        // Attempt 3: non-structured tanpa reasoning
        #expect(bodies[2]["response_format"] == nil)
        #expect(bodies[2]["reasoning"] == nil)
    }

    @Test("Semua attempt no-endpoints → pesan arahkan ganti model di Pengaturan")
    func noEndpointsAllFail() async {
        RoutingMockURLProtocol.handler = { _ in
            (404, Data(#"{"error":{"message":"No endpoints found that can handle the requested parameters."}}"#.utf8))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        do {
            _ = try await parser.parse("x")
            Issue.record("harus melempar")
        } catch let error as TransactionParsingError {
            #expect(error.errorDescription?.contains("Model AI") == true)
        } catch { Issue.record("tipe error salah") }
    }

    @Test("parseEntry: kalimat utang → DebtDraft; kalimat belanja → TransactionDraft")
    func parseEntryDebtVsTransaction() async throws {
        let debtResult = """
        {"record_kind":"debt","amount":50000,"type":"expense","days_ago":0,"merchant":"","note":"pinjam uang","category_name":"","subcategory_name":"","counterparty":"Budi","direction":"i_owe"}
        """
        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": debtResult]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        guard case .debt(let draft) = try await parser.parseEntry("utang ke Budi 50k") else {
            Issue.record("harus debt"); return
        }
        #expect(draft.counterparty == "Budi")
        #expect(draft.direction == .iOwe)
        #expect(draft.amount == 50000)
        #expect(draft.rawInput == "utang ke Budi 50k")

        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": self.result]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        guard case .transaction(let tx) = try await parser.parseEntry("beli bakso 20k") else {
            Issue.record("harus transaksi"); return
        }
        #expect(tx.amount == 20000)
    }

    @Test("Structured tapi content bocor teks di sekitar JSON (gpt-oss harmony) → tetap ter-decode")
    func structuredWithLeakedText() async throws {
        // Reproduksi pola live user: JSON valid + baris nyasar setelahnya
        // ("Unexpected character 'd' around line 6").
        let leaked = "{\n\"amount\":20000,\n\"type\":\"expense\",\n\"days_ago\":0,\n\"merchant\":\"\",\n\"note\":\"bakso\",\n\"category_name\":\"\",\n\"subcategory_name\":\"\",\n\"record_kind\":\"transaction\",\n\"counterparty\":\"\",\n\"direction\":\"none\"\n}\ndone"
        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": leaked]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        let draft = try await parser.parse("beli bakso 20k")
        #expect(draft.amount == 20000)
        #expect(draft.note == "bakso")
    }

    @Test("Decode lentur: amount sbg string + field hilang → tetap sukses")
    func lenientFieldDecode() async throws {
        // Sebagian model kirim amount sbg string & melewatkan field opsional.
        let loose = #"{"amount":"20.000","type":"expense"}"#
        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": loose]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        let draft = try await parser.parse("beli sesuatu 20k")
        #expect(draft.amount == 20000)
        #expect(draft.type == .expense)
    }

    @Test("Decode double-encoded: content = string JSON berisi objek")
    func doubleEncodedContent() async throws {
        // content adalah STRING JSON (objek ter-escape) — bukan objek langsung.
        RoutingMockURLProtocol.handler = { _ in
            let inner = #"{"amount":15000,"type":"expense","days_ago":0,"merchant":"","note":"kopi","category_name":"","subcategory_name":"","record_kind":"transaction","counterparty":"","direction":"none"}"#
            let json = ["choices": [["message": ["content": inner]]]]  // sudah string
            // Bungkus lagi jadi string ganda:
            let doubled = ["choices": [["message": ["content": String(data: try! JSONSerialization.data(withJSONObject: ["x": inner]), encoding: .utf8)!]]]]
            _ = json
            // Kirim content = JSON-string murni (bukan objek): "\"{...}\""
            let stringContent = try! String(data: JSONEncoder().encode(inner), encoding: .utf8)!
            _ = doubled
            let payload = ["choices": [["message": ["content": stringContent]]]]
            return (200, try! JSONSerialization.data(withJSONObject: payload))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        let draft = try await parser.parse("kopi 15k")
        #expect(draft.amount == 15000)
        #expect(draft.note == "kopi")
    }

    @Test("Model balas key-value/YAML (gpt-oss abai JSON) → parseEntry tetap dapat DebtDraft")
    func keyValueFallbackDebt() async throws {
        // Payload live persis dari gpt-oss-20b:free: alias owner/keterangan/category.
        let yaml = "keterangan: utang ke rea 10k kopi\namount: 10000\nowner: i_owe\ncounterparty: Rea\nrecord_kind: debt\ncategory: \"\" 🙃"
        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": yaml]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        guard case .debt(let draft) = try await parser.parseEntry("utang ke rea 10k kopi") else {
            Issue.record("harus debt"); return
        }
        #expect(draft.counterparty == "Rea")
        #expect(draft.direction == .iOwe)
        #expect(draft.amount == 10000)
        #expect(draft.note == "utang ke rea 10k kopi")
    }

    @Test("Key-value tanpa nominal → nil (jangan terima teks acak)")
    func keyValueRejectsGarbage() async {
        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": "halo apa kabar\nini bukan transaksi"]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        await #expect(throws: TransactionParsingError.self) {
            _ = try await parser.parse("halo")
        }
    }

    @Test("record_kind debt TANPA counterparty → jatuh ke transaksi (guard isDebt)")
    func debtWithoutCounterpartyFallsBack() async throws {
        let odd = """
        {"record_kind":"debt","amount":50000,"type":"expense","days_ago":0,"merchant":"","note":"","category_name":"","subcategory_name":"","counterparty":"  ","direction":"i_owe"}
        """
        RoutingMockURLProtocol.handler = { _ in
            let json = ["choices": [["message": ["content": odd]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let parser = makeOpenRouterParser(store: MockModelPreferenceStore())
        guard case .transaction = try await parser.parseEntry("x") else {
            Issue.record("harus jatuh ke transaksi"); return
        }
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
