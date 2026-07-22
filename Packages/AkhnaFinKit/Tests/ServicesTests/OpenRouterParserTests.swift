import Testing
import Foundation
import AkhnaFinCore
import ServiceInterfaces
@testable import Services

/// Personalisasi palsu — snippet konstan, catat input yang diminta.
private struct StubPersonalization: PersonalizationProviding {
    let snippet: String
    func contextSnippet(for input: String) async -> String { snippet }
}

/// URLProtocol khusus suite ini — handler statis TERPISAH dari
/// `MockURLProtocol` (OpenRouterClientTests) supaya dua suite yang jalan
/// paralel tidak saling menimpa handler.
final class ParserMockURLProtocol: URLProtocol {
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

@Suite("OpenRouterParser — 2-stage via client mock", .serialized)
struct OpenRouterParserTests {
    /// Client dgn URLProtocol mock: bedakan stage dari field `model` body.
    private func makeParser(
        stage1: String,
        stage2: String,
        personalization: (any PersonalizationProviding)? = nil,
        onRequest: (@Sendable ([String: Any]) -> Void)? = nil
    ) -> OpenRouterParser {
        ParserMockURLProtocol.handler = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
            onRequest?(body)
            let model = body["model"] as! String
            let content = model == OpenRouterModel.perception ? stage1 : stage2
            let json = ["choices": [["message": ["content": content]]]]
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ParserMockURLProtocol.self]
        let keyStore = MockAPIKeyStore(initialKey: "sk-or-test")
        return OpenRouterParser(
            client: OpenRouterClient(keyStore: keyStore, session: URLSession(configuration: config)),
            keyStore: keyStore,
            categoryNames: ["Main Food", "Tagihan"],
            subcategoryNames: ["Jajan"],
            personalization: personalization
        )
    }

    private let stage1Facts = """
    {"amount":20000,"kind":"expense","days_ago":1,"merchant":"Kantin Kantor","bank":"","note":"bakso"}
    """
    private let stage2Result = """
    {"amount":20000,"type":"expense","days_ago":1,"merchant":"Kantin Kantor","note":"bakso","category_name":"Main Food","subcategory_name":""}
    """

    @Test("parse teks: dua stage → draft lengkap + rawInput")
    func parseTwoStage() async throws {
        let parser = makeParser(stage1: stage1Facts, stage2: stage2Result)
        let draft = try await parser.parse("beli bakso 20k kemarin di kantin")
        #expect(draft.amount == 20000)
        #expect(draft.type == .expense)
        #expect(draft.merchant == "Kantin Kantor")
        #expect(draft.categoryName == "Main Food")
        #expect(draft.rawInput == "beli bakso 20k kemarin di kantin")
        let calendar = Calendar.current
        #expect(calendar.isDate(draft.date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: .now)!))
    }

    @Test("parseReceipt: gambar dikirim ke model perception sbg image_url")
    func receiptSendsImage() async throws {
        nonisolated(unsafe) var sawImagePart = false
        let parser = makeParser(stage1: stage1Facts, stage2: stage2Result) { body in
            if body["model"] as! String == OpenRouterModel.perception {
                let messages = body["messages"] as! [[String: Any]]
                let parts = messages.last!["content"] as! [[String: Any]]
                if parts.contains(where: { $0["type"] as? String == "image_url" }) {
                    sawImagePart = true
                }
            }
        }
        let draft = try await parser.parseReceipt(image: Data([0xFF, 0xD8]))
        #expect(sawImagePart)
        #expect(draft.amount == 20000)
    }

    @Test("Snippet personalisasi masuk ke instruksi stage 2")
    func personalizationInjected() async throws {
        nonisolated(unsafe) var stage2System = ""
        let parser = makeParser(
            stage1: stage1Facts,
            stage2: stage2Result,
            personalization: StubPersonalization(snippet: "indomaret → Main Food (kuat)")
        ) { body in
            if body["model"] as! String == OpenRouterModel.generator {
                let messages = body["messages"] as! [[String: Any]]
                let parts = messages.first!["content"] as! [[String: Any]]
                stage2System = parts.first!["text"] as! String
            }
        }
        _ = try await parser.parse("belanja indomaret 50k")
        #expect(stage2System.contains("indomaret → Main Food"))
    }

    @Test("availability mengikuti keberadaan key")
    func availabilityFollowsKey() {
        let empty = OpenRouterParser(
            client: OpenRouterClient(keyStore: MockAPIKeyStore()),
            keyStore: MockAPIKeyStore(),
            categoryNames: [], subcategoryNames: []
        )
        #expect(empty.availability != .available)
        let keyed = OpenRouterParser(
            client: OpenRouterClient(keyStore: MockAPIKeyStore(initialKey: "k")),
            keyStore: MockAPIKeyStore(initialKey: "k"),
            categoryNames: [], subcategoryNames: []
        )
        #expect(keyed.availability == .available)
    }

    @Test("Stage 1 JSON rusak → parsingFailed siap-tampil")
    func malformedStage1() async {
        let parser = makeParser(stage1: "bukan json", stage2: stage2Result)
        do {
            _ = try await parser.parse("x")
            Issue.record("harus melempar")
        } catch let error as TransactionParsingError {
            #expect(error.errorDescription?.isEmpty == false)
        } catch { Issue.record("tipe error salah") }
    }

    // MARK: - Mapping murni (port dari suite lama ServicesTests)

    @Test("Mapping GeneratedTransaction → draft: type tak dikenal → expense, daysAgo negatif → hari ini, amount negatif → 0")
    func mappingEdgeCases() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 20))!
        let odd = OpenRouterParser.GeneratedTransaction(
            amount: -5, type: "belanja", daysAgo: -3,
            merchant: "", note: "", categoryName: "", subcategoryName: ""
        )
        let draft = odd.draft(rawInput: "raw", now: now, calendar: calendar)
        #expect(draft.amount == 0)
        #expect(draft.type == .expense)
        #expect(calendar.isDate(draft.date, inSameDayAs: now))
        #expect(draft.rawInput == "raw")
    }

    @Test("extractJSONObject: bersih dari fences/prosa/reasoning")
    func jsonExtraction() throws {
        func extract(_ s: String) -> String? {
            OpenRouterParser.extractJSONObject(from: Data(s.utf8))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        #expect(extract("```json\n{\"a\":1}\n```") == "{\"a\":1}")
        #expect(extract("Sure! Here it is: {\"a\": {\"b\": 2}} done.") == "{\"a\": {\"b\": 2}}")
        // Kurung dalam string literal tidak mengganggu penghitungan.
        #expect(extract(#"{"note":"harga {promo}"}"#) == #"{"note":"harga {promo}"}"#)
        #expect(extract("no json here") == nil)
    }

    @Test("Stage 1 membungkus JSON dgn fences → tetap ter-decode")
    func stage1WithFences() async throws {
        let parser = makeParser(
            stage1: "```json\n\(stage1Facts)\n```",
            stage2: stage2Result
        )
        let draft = try await parser.parse("beli bakso 20k")
        #expect(draft.amount == 20000)
    }

    @Test("sanitizedRupiah membulatkan artefak floating point")
    func rupiahSanitizer() {
        #expect(sanitizedRupiah(19999.999999999996) == 20000)
        #expect(sanitizedRupiah(-10) == 0)
        #expect(sanitizedRupiah(12500.4) == Decimal(string: "12500.4"))
    }
}
