import Foundation
import OSLog
import AkhnaFinCore
import ServiceInterfaces

private let parserLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Parser")
private let parserSignposter = OSSignposter(subsystem: "com.aban.AkhnaFin", category: "Parser")

/// Parser 2-stage berbasis OpenRouter (PLAN-006):
///
/// 1. **Perception** (`OpenRouterModel.perception`, multimodal): teks bahasa
///    natural APA PUN (Indonesia/English) ATAU foto resi → fakta ternormalisasi.
/// 2. **Generator** (`OpenRouterModel.generator`, structured outputs): fakta +
///    daftar kategori user + konteks personalisasi → `TransactionDraft`.
///
/// Hasil SELALU draft yang dikonfirmasi user — pipeline sakral tak berubah.
public struct OpenRouterParser: TransactionParsing {
    private let client: OpenRouterClient
    private let keyStore: any APIKeyStoring
    private let categoryNames: [String]
    private let subcategoryNames: [String]
    private let personalization: (any PersonalizationProviding)?

    public init(
        client: OpenRouterClient,
        keyStore: any APIKeyStoring,
        categoryNames: [String],
        subcategoryNames: [String],
        personalization: (any PersonalizationProviding)? = nil
    ) {
        self.client = client
        self.keyStore = keyStore
        self.categoryNames = categoryNames
        self.subcategoryNames = subcategoryNames
        self.personalization = personalization
    }

    public var availability: ParsingAvailability {
        if let key = keyStore.read(), !key.isEmpty {
            return .available
        }
        return .unavailable(
            reason: "Masukkan API key OpenRouter di Pengaturan untuk mengaktifkan pencatatan AI."
        )
    }

    // MARK: - TransactionParsing

    public func parse(_ text: String) async throws -> TransactionDraft {
        let interval = parserSignposter.beginInterval("parse")
        defer { parserSignposter.endInterval("parse", interval) }
        let facts = try await perceive(parts: [.text(text)], hint: .sentence)
        let draft = try await generate(from: facts, rawInput: text)
        parserLog.info("parse sukses (\(text.count) chars)")
        return draft
    }

    public func parseBatch(_ text: String) async throws -> [TransactionDraft] {
        var drafts: [TransactionDraft] = []
        for line in text.split(whereSeparator: \.isNewline) {
            drafts.append(try await parse(String(line)))
        }
        return drafts
    }

    public func parseReceipt(image: Data) async throws -> TransactionDraft {
        let interval = parserSignposter.beginInterval("parse")
        defer { parserSignposter.endInterval("parse", interval) }
        let facts = try await perceive(parts: [.image(image)], hint: .receipt)
        let draft = try await generate(from: facts, rawInput: "")
        parserLog.info("parseReceipt sukses (\(image.count) bytes)")
        return draft
    }

    // MARK: - Stage 1: Perception (Nemotron omni)

    enum InputHint { case sentence, receipt }

    struct PerceivedFacts: Decodable {
        let amount: Double
        let kind: String
        let daysAgo: Int
        let merchant: String
        let bank: String
        let note: String

        enum CodingKeys: String, CodingKey {
            case amount, kind, merchant, bank, note
            case daysAgo = "days_ago"
        }
    }

    private static let perceptionSchema = """
    {"type":"object","properties":{"amount":{"type":"number","description":"Transaction amount in full rupiah. k=thousand (20k=20000), m/jt=million. For receipts: the FINAL GRAND TOTAL paid."},"kind":{"type":"string","enum":["expense","income","transfer"]},"days_ago":{"type":"integer","description":"today=0, yesterday/kemarin=1, two days ago/kemarin lusa=2"},"merchant":{"type":"string","description":"Store/seller/place name; empty if unknown"},"bank":{"type":"string","description":"Bank or payment app mentioned (BCA, GoPay, SPayLater, ...); empty if none"},"note":{"type":"string","description":"Short summary of items/services bought"}},"required":["amount","kind","days_ago","merchant","bank","note"],"additionalProperties":false}
    """

    private func perceive(parts: [ORContentPart], hint: InputHint) async throws -> PerceivedFacts {
        let instruction = switch hint {
        case .sentence:
            """
            You are a perception module of a personal-finance app. Extract normalized \
            facts from the user's sentence. The sentence may be Indonesian or English. \
            Amount rules: k=×1000, jt/m=×1000000; never round or add zeros.
            """
        case .receipt:
            """
            You are a perception module of a personal-finance app. Read this shopping \
            receipt image (usually Indonesian). Extract the FINAL grand total actually \
            paid (after discounts/tax — the largest TOTAL line), the merchant name, and \
            summarize the items briefly in `note`. kind is always "expense", days_ago 0 \
            unless a clear date shows otherwise.
            """
        }
        // Nemotron omni :free TAK dukung structured outputs → structured:false,
        // minta JSON lewat prompt, lalu ekstrak objek JSON secara toleran
        // (model reasoning bisa menyisipkan penjelasan/markdown).
        let promptJSON = instruction + """


        Return ONLY a single JSON object, no markdown fences, no commentary:
        {"amount": number (full rupiah), "kind": "expense"|"income"|"transfer", \
        "days_ago": integer, "merchant": string, "bank": string, "note": string}
        """
        let data = try await client.completeStructured(
            model: OpenRouterModel.perception,
            messages: [.system(promptJSON), .user(parts)],
            schemaName: "perceived_facts",
            schemaJSON: Self.perceptionSchema,
            structured: false
        )
        guard let jsonData = Self.extractJSONObject(from: data),
              let facts = try? JSONDecoder().decode(PerceivedFacts.self, from: jsonData) else {
            parserLog.error("decode stage1 gagal (\(data.count) bytes)")
            throw TransactionParsingError.parsingFailed(
                "Gagal memahami input itu. Coba tulis ulang lebih jelas."
            )
        }
        return facts
    }

    // MARK: - Stage 2: Transaction generator (gpt-oss-120b)

    struct GeneratedTransaction: Decodable {
        let amount: Double
        let type: String
        let daysAgo: Int
        let merchant: String
        let note: String
        let categoryName: String
        let subcategoryName: String

        enum CodingKeys: String, CodingKey {
            case amount, type, merchant, note
            case daysAgo = "days_ago"
            case categoryName = "category_name"
            case subcategoryName = "subcategory_name"
        }

        /// Mapping murni (tanpa network) ke draft — unit-testable.
        func draft(rawInput: String, now: Date = .now, calendar: Calendar = .current) -> TransactionDraft {
            let daysBack = max(0, daysAgo)
            let date = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
            return TransactionDraft(
                amount: sanitizedRupiah(amount),
                type: TransactionType(rawValue: type) ?? .expense,
                date: date,
                note: note,
                merchant: merchant,
                categoryName: categoryName,
                subcategoryName: subcategoryName,
                rawInput: rawInput
            )
        }
    }

    private static let generationSchema = """
    {"type":"object","properties":{"amount":{"type":"number"},"type":{"type":"string","enum":["expense","income","transfer"]},"days_ago":{"type":"integer"},"merchant":{"type":"string"},"note":{"type":"string"},"category_name":{"type":"string","description":"Best-matching MAIN category name from the provided list; empty if unsure"},"subcategory_name":{"type":"string","description":"Matching subcategory from the provided list; empty otherwise"}},"required":["amount","type","days_ago","merchant","note","category_name","subcategory_name"],"additionalProperties":false}
    """

    private func generate(from facts: PerceivedFacts, rawInput: String) async throws -> TransactionDraft {
        var instruction = """
        You are the transaction generator of a personal-finance app. Given normalized \
        facts, produce the final transaction. Copy amount/days_ago faithfully — never \
        round, never invent digits.
        Available main categories: \(Self.describe(categoryNames)).
        Available subcategories: \(Self.describe(subcategoryNames)).
        Category names are Indonesian. Output the exact NAME, only from those lists; \
        empty string if unsure.
        """
        // Konteks personalisasi (knowledge-graph mini): asosiasi kebiasaan user —
        // merchant/bank/kata → kategori. Prioritaskan bila relevan.
        if let personalization {
            let snippet = await personalization.contextSnippet(
                for: [rawInput, facts.merchant, facts.bank, facts.note].joined(separator: " ")
            )
            if !snippet.isEmpty {
                instruction += "\n\nUser's known category habits (strong hints, follow when relevant):\n\(snippet)"
            }
        }

        let factsJSON = """
        {"amount":\(facts.amount),"kind":"\(facts.kind)","days_ago":\(facts.daysAgo),\
        "merchant":"\(Self.escaped(facts.merchant))","bank":"\(Self.escaped(facts.bank))",\
        "note":"\(Self.escaped(facts.note))"}
        """
        let data = try await client.completeStructured(
            model: OpenRouterModel.generator,
            messages: [.system(instruction), .user([.text(factsJSON)])],
            schemaName: "generated_transaction",
            schemaJSON: Self.generationSchema
        )
        do {
            let generated = try JSONDecoder().decode(GeneratedTransaction.self, from: data)
            return generated.draft(rawInput: rawInput)
        } catch {
            parserLog.error("decode stage2 gagal: \(String(describing: error), privacy: .public)")
            throw TransactionParsingError.parsingFailed("Gagal menyusun transaksi. Coba lagi.")
        }
    }

    // MARK: - Glossary kategori (port dari parser lama — BUG-1a)

    private static let glossary: [String: String] = [
        "Main Food": "daily meals",
        "Lifestyle": "leisure & hobbies",
        "Jajan": "snacks / street food / coffee",
        "Hiburan": "entertainment: movies, games, streaming, concerts",
        "Olahraga": "sports & fitness: gym, badminton, futsal, swimming, running gear",
        "Tagihan": "bills & utilities: electricity, water, internet, rent, subscriptions",
        "Transport": "transportation: fuel, parking, ride-hailing, public transit",
        "Kesehatan": "health & medical",
        "Gaji": "salary / wages",
        "Bonus": "bonus / incentives / gifts received",
    ]

    private static func describe(_ names: [String]) -> String {
        names
            .map { name in glossary[name].map { "\(name) (= \($0))" } ?? name }
            .joined(separator: ", ")
    }

    /// Ekstrak objek JSON pertama yang seimbang dari respons non-structured
    /// (model reasoning bisa membungkus dengan ```json fences atau prosa).
    /// Menghitung kurung dengan menghormati string literal & escape.
    static func extractJSONObject(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
            } else {
                switch char {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index]).data(using: .utf8)
                    }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func escaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

/// Double → Decimal dibulatkan 2 digit (hindari artefak floating-point), minimum 0.
/// (Dipindah dari FoundationModelsParser saat pivot PLAN-006.)
func sanitizedRupiah(_ amount: Double) -> Decimal {
    var value = Decimal(max(0, amount))
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 2, .plain)
    return rounded
}
