import Foundation
import OSLog
import AkhnaFinCore
import ServiceInterfaces

private let parserLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Parser")
private let parserSignposter = OSSignposter(subsystem: "com.aban.AkhnaFin", category: "Parser")

/// Parser SATU-CALL berbasis OpenRouter (PLAN-006, disederhanakan dari 2-stage
/// awal setelah pengukuran live: 2 call berantai = 23.2s; model tunggal
/// memangkas satu round-trip network penuh).
///
/// Satu model multimodal (`OpenRouterModel.model`) mengerjakan sekaligus:
/// teks (Indonesia/English) ATAU foto resi → ekstraksi fakta + tebakan
/// kategori (dibantu daftar kategori user + konteks personalisasi
/// `CategorySignal`). Hasil SELALU draft yang dikonfirmasi user.
///
/// Trade-off sadar: personalisasi hanya bisa disuntik SEBELUM call untuk jalur
/// teks (merchant belum diketahui untuk resi sampai model membacanya sendiri
/// di call yang sama) — kategori resi tetap bisa benar lewat daftar kategori
/// di prompt, hanya tanpa dorongan riwayat personal di kesempatan itu.
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
        // Personalisasi bisa disuntik SEBELUM call: teks mentah sudah berisi
        // kandidat merchant/keyword.
        let snippet = await personalization?.contextSnippet(for: text) ?? ""
        return try await complete(parts: [.text(text)], hint: .sentence, personalizationSnippet: snippet, rawInput: text)
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
        // Tanpa personalisasi pre-call: merchant resi belum diketahui sebelum
        // model membaca gambar di call yang sama (trade-off single-stage).
        return try await complete(parts: [.image(image)], hint: .receipt, personalizationSnippet: "", rawInput: "")
    }

    // MARK: - Satu call: persepsi + kategorisasi

    private enum InputHint { case sentence, receipt }

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

    private static let schema = """
    {"type":"object","properties":{"amount":{"type":"number","description":"Transaction amount in full rupiah. k=thousand (20k=20000), m/jt=million. For receipts: the FINAL GRAND TOTAL paid."},"type":{"type":"string","enum":["expense","income","transfer"]},"days_ago":{"type":"integer","description":"today=0, yesterday/kemarin=1, two days ago/kemarin lusa=2"},"merchant":{"type":"string","description":"Store/seller/place name; empty if unknown"},"note":{"type":"string","description":"Short summary of items/services bought"},"category_name":{"type":"string","description":"Best-matching MAIN category name from the provided list; empty if unsure"},"subcategory_name":{"type":"string","description":"Matching subcategory from the provided list; empty otherwise"}},"required":["amount","type","days_ago","merchant","note","category_name","subcategory_name"],"additionalProperties":false}
    """

    private func complete(
        parts: [ORContentPart],
        hint: InputHint,
        personalizationSnippet: String,
        rawInput: String
    ) async throws -> TransactionDraft {
        var instruction = switch hint {
        case .sentence:
            """
            You are a personal-finance parser. Convert the user's sentence (Indonesian \
            or English) into a structured transaction. Amount rules: k=×1000, jt/m=×1000000; \
            never round or add zeros.
            """
        case .receipt:
            """
            You are a personal-finance parser reading a shopping receipt image (usually \
            Indonesian). Extract the FINAL grand total actually paid (after discounts/tax \
            — the largest TOTAL line), the merchant name, and summarize items briefly in \
            `note`. type is always "expense", days_ago 0 unless a clear date shows otherwise.
            """
        }
        instruction += """

        Available main categories: \(Self.describe(categoryNames)).
        Available subcategories: \(Self.describe(subcategoryNames)).
        Category names are Indonesian. Output the exact NAME, only from those lists; \
        empty string if unsure.
        """
        if !personalizationSnippet.isEmpty {
            instruction += "\n\nUser's known category habits (strong hints, follow when relevant):\n\(personalizationSnippet)"
        }

        let clock = ContinuousClock()
        let start = clock.now
        let data = try await client.completeStructured(
            model: OpenRouterModel.model,
            messages: [.system(instruction), .user(parts)],
            schemaName: "generated_transaction",
            schemaJSON: Self.schema
        )
        parserLog.info("call selesai dalam \(clock.now - start, privacy: .public)")

        do {
            let generated = try JSONDecoder().decode(GeneratedTransaction.self, from: data)
            return generated.draft(rawInput: rawInput)
        } catch {
            parserLog.error("decode gagal: \(String(describing: error), privacy: .public)")
            throw TransactionParsingError.parsingFailed(
                "Gagal memahami input itu. Coba tulis ulang lebih jelas."
            )
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
}

/// Double → Decimal dibulatkan 2 digit (hindari artefak floating-point), minimum 0.
/// (Dipindah dari FoundationModelsParser saat pivot PLAN-006.)
func sanitizedRupiah(_ amount: Double) -> Decimal {
    var value = Decimal(max(0, amount))
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 2, .plain)
    return rounded
}
