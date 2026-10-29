import Foundation
import OSLog
import AkhnaFinCore
import ServiceInterfaces

private let glmLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Parser")

struct GLMParsedTransaction: Decodable {
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

public struct GLMTransactionParser: TransactionParsing {
    private let client: InferenceClient
    private let keyStore: any APIKeyStoring
    private let categoryNames: [String]
    private let subcategoryNames: [String]

    public init(
        client: InferenceClient,
        keyStore: any APIKeyStoring,
        categoryNames: [String],
        subcategoryNames: [String]
    ) {
        self.client = client
        self.keyStore = keyStore
        self.categoryNames = categoryNames
        self.subcategoryNames = subcategoryNames
    }

    public var availability: ParsingAvailability {
        if let key = keyStore.read(), !key.isEmpty {
            return .available
        }
        return .unavailable(
            reason: "Masukkan API key W&B di Pengaturan untuk mengaktifkan pencatatan AI."
        )
    }

    public func parse(_ text: String) async throws -> TransactionDraft {
        let content = try await client.complete(system: sentencePrompt, user: text)
        let parsed = try Self.decode(content)
        glmLog.info("parse sukses (\(text.count) chars input)")
        return parsed.draft(rawInput: text)
    }

    public func parseBatch(_ text: String) async throws -> [TransactionDraft] {
        var drafts: [TransactionDraft] = []
        for line in text.split(whereSeparator: \.isNewline) {
            drafts.append(try await parse(String(line)))
        }
        return drafts
    }

    public func parseReceipt(text: String) async throws -> TransactionDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TransactionParsingError.parsingFailed(
                "Resi tidak terbaca. Coba screenshot ulang dengan lebih jelas."
            )
        }

        // Jalur offline: tanpa key, resi tetap bisa diproses heuristik lokal.
        guard keyStore.read()?.isEmpty == false else {
            return try heuristicsDraft(from: trimmed)
        }

        do {
            let content = try await client.complete(system: receiptPrompt, user: trimmed)
            let parsed = try Self.decode(content)
            glmLog.info("parseReceipt sukses (GLM, \(trimmed.count) chars OCR)")
            return parsed.draft(rawInput: String(trimmed.prefix(500)))
        } catch {
            glmLog.error("parseReceipt GLM gagal, jatuh ke heuristik: \(String(describing: error), privacy: .public)")
            return try heuristicsDraft(from: trimmed)
        }
    }

    private func heuristicsDraft(from ocrText: String) throws -> TransactionDraft {
        guard let draft = ReceiptHeuristics.draft(from: ocrText) else {
            throw TransactionParsingError.parsingFailed(
                "Tidak menemukan nominal total di resi. Pastikan baris TOTAL terlihat di screenshot."
            )
        }
        return draft
    }

    static func decode(_ content: String) throws -> GLMParsedTransaction {
        guard let data = Self.extractJSON(from: content) else {
            throw TransactionParsingError.parsingFailed(
                "Gagal memahami balasan model. Coba tulis ulang lebih jelas."
            )
        }
        do {
            return try JSONDecoder().decode(GLMParsedTransaction.self, from: data)
        } catch {
            throw TransactionParsingError.parsingFailed(
                "Gagal memahami balasan model. Coba tulis ulang lebih jelas."
            )
        }
    }

    static func extractJSON(from content: String) -> Data? {
        var text = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        text = String(text[start...end])
        return Data(text.utf8)
    }

    private var sentencePrompt: String {
        """
        You are the transaction parser of an Indonesian personal-finance app. \
        Parse the user's sentence — it may be Indonesian OR English — into JSON.

        Amount rules: "k" = x1000 ("20k" = 20000, "35k" = 35000); \
        "jt" and "m" = x1000000 ("2.5m" = 2500000, "5.73jt" = 5730000). \
        Never round, never add extra zeros, never drop digits.
        Relative days from today: today = 0, kemarin/yesterday = 1, \
        kemarin lusa/two days ago = 2.
        Transaction kind: a purchase or payment = "expense"; salary/bonus/incoming \
        money = "income"; moving funds between own accounts = "transfer".

        Available main categories (output the exact name ONLY from this list; \
        empty string if unsure): \(Self.describe(categoryNames)).
        Available subcategories: \(Self.describe(subcategoryNames)).

        Output ONLY raw JSON (no markdown, no explanation) matching exactly:
        {"amount":0,"type":"expense","days_ago":0,"merchant":"","note":"","category_name":"","subcategory_name":""}
        """
    }

    private var receiptPrompt: String {
        """
        You are the receipt parser of an Indonesian personal-finance app. \
        The user message is OCR text from a shopping receipt (usually Indonesian).

        Extract: the FINAL grand total actually paid (after discounts and tax — \
        usually the largest TOTAL/JUMLAH line, never "kembali"/change), the merchant \
        name, a short item summary in "note", and the best-matching category.
        "type" is always "expense". "days_ago" is 0 unless the receipt shows a \
        clear past date.
        Ignore phone numbers, addresses, and cashier names.

        Available main categories: \(Self.describe(categoryNames)).
        Available subcategories: \(Self.describe(subcategoryNames)).

        Output ONLY raw JSON (no markdown, no explanation) matching exactly:
        {"amount":0,"type":"expense","days_ago":0,"merchant":"","note":"","category_name":"","subcategory_name":""}
        """
    }

    private static let glossary: [String: String] = [
        "Main Food": "daily meals",
        "Lifestyle": "leisure & hobbies",
        "Jajan": "snacks / street food / coffee",
        "Hiburan": "entertainment: movies, games, streaming",
        "Olahraga": "sports & fitness: gym, badminton, futsal, swimming",
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