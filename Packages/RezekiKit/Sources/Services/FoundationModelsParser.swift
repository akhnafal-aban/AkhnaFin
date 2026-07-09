import Foundation
import FoundationModels
import OSLog
import RezekiCore
import ServiceInterfaces

private let parserLog = Logger(subsystem: "com.aban.My-RezekiKu", category: "Parser")
private let parserSignposter = OSSignposter(subsystem: "com.aban.My-RezekiKu", category: "Parser")

/// Skema terstruktur yang dihasilkan model on-device (guided generation).
///
/// Dipisah dari `TransactionDraft` agar `ServiceInterfaces` tetap bebas dependensi
/// framework AI — mapping ke draft dilakukan di `draft(rawInput:now:calendar:)`.
@Generable
struct ParsedTransaction {
    @Guide(description: "Transaction amount in full Rupiah. k = thousand, m/jt = million. Example: '20k' = 20000, '1.5m' = 1500000")
    var amount: Double

    @Guide(description: "Transaction kind: a purchase or payment = expense; salary/bonus/incoming money = income; moving funds between accounts = transfer", .anyOf(["expense", "income", "transfer"]))
    var type: String

    @Guide(description: "How many days ago the transaction happened: today = 0, yesterday = 1, two days ago = 2")
    var daysAgo: Int

    @Guide(description: "Merchant/place/seller name if mentioned, empty string otherwise")
    var merchant: String

    @Guide(description: "Item/service bought or a short description of the transaction")
    var note: String

    @Guide(description: "Best-matching main category name, ONLY from the list in the instructions; empty string if unsure")
    var categoryName: String

    @Guide(description: "Matching subcategory name from the list in the instructions if any; empty string otherwise")
    var subcategoryName: String

    // Macro @Generable menambahkan init(_:) sehingga memberwise init implisit hilang —
    // init eksplisit ini dipakai unit test mapper.
    init(
        amount: Double,
        type: String,
        daysAgo: Int,
        merchant: String = "",
        note: String = "",
        categoryName: String = "",
        subcategoryName: String = ""
    ) {
        self.amount = amount
        self.type = type
        self.daysAgo = daysAgo
        self.merchant = merchant
        self.note = note
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
    }
}

extension ParsedTransaction {
    /// Mapping murni (tanpa model) ke `TransactionDraft` — unit-testable.
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

/// Double → Decimal dibulatkan 2 digit (hindari artefak floating-point), minimum 0.
/// Dipakai mapper kalimat & resi — satu sumber kebenaran.
func sanitizedRupiah(_ amount: Double) -> Decimal {
    var value = Decimal(max(0, amount))
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 2, .plain)
    return rounded
}


/// Parser natural language berbasis Foundation Models (on-device, iOS 26+).
///
/// Tanpa heuristic fallback: bila model tidak tersedia, `availability` menjelaskan
/// alasannya dan `parse` melempar — UI menampilkan graceful state.
public struct FoundationModelsParser: TransactionParsing {
    private let categoryNames: [String]
    private let subcategoryNames: [String]

    public init(categoryNames: [String], subcategoryNames: [String]) {
        self.categoryNames = categoryNames
        self.subcategoryNames = subcategoryNames
    }

    public var availability: ParsingAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(reason: Self.describe(reason))
        }
    }

    public func parse(_ text: String) async throws -> TransactionDraft {
        guard case .available = availability else {
            if case .unavailable(let reason) = availability {
                throw TransactionParsingError.modelUnavailable(reason)
            }
            throw TransactionParsingError.modelUnavailable("Model tidak tersedia.")
        }
        // Session baru per permintaan: parsing bersifat stateless, transcript
        // yang menumpuk hanya membengkakkan konteks.
        let session = LanguageModelSession(instructions: instructions)
        let interval = parserSignposter.beginInterval("parse")
        defer { parserSignposter.endInterval("parse", interval) }
        do {
            // Greedy sampling: output deterministik — kualitas terukur & stabil (BUG-1a).
            let response = try await session.respond(
                to: text,
                generating: ParsedTransaction.self,
                options: GenerationOptions(sampling: .greedy)
            )
            parserLog.info("parse sukses (\(text.count) chars input)")
            return response.content.draft(rawInput: text)
        } catch {
            parserLog.error("FoundationModels respond gagal: \(String(describing: error), privacy: .public)")
            throw TransactionParsingError.parsingFailed(
                "Gagal memahami kalimat itu. Tulis dalam Bahasa Inggris, mis. \"buy meatballs 20k at the canteen\"."
            )
        }
    }

    public func parseBatch(_ text: String) async throws -> [TransactionDraft] {
        var drafts: [TransactionDraft] = []
        for line in text.split(whereSeparator: \.isNewline) {
            drafts.append(try await parse(String(line)))
        }
        return drafts
    }

    /// Resi: mesin DETERMINISTIK (`ReceiptHeuristics`), bukan LLM — Foundation
    /// Models menolak semua prompt berisi teks Indonesia (`unsupportedLanguage
    /// OrLocale`, terverifikasi empiris, amplop English pun tidak lolos), dan
    /// resi Indonesia pasti berisi kata Indonesia. Bonus: jalur ini bekerja
    /// meski Apple Intelligence tidak tersedia.
    public func parseReceipt(text: String) async throws -> TransactionDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TransactionParsingError.parsingFailed(
                "Resi tidak terbaca. Coba screenshot ulang dengan lebih jelas."
            )
        }
        let interval = parserSignposter.beginInterval("parse")
        defer { parserSignposter.endInterval("parse", interval) }
        guard let draft = ReceiptHeuristics.draft(from: trimmed) else {
            parserLog.error("parseReceipt: total tidak ditemukan (\(trimmed.count) chars OCR)")
            throw TransactionParsingError.parsingFailed(
                "Tidak menemukan nominal total di resi. Pastikan baris TOTAL terlihat di screenshot."
            )
        }
        parserLog.info("parseReceipt sukses (heuristik, \(trimmed.count) chars OCR)")
        return draft
    }

    private var instructions: String {
        """
        You are a personal-finance parser. Convert the user's English sentence into \
        structured transaction data.
        Amount rules: "k" = ×1000, "m" = ×1000000. "20k" = 20000. "250k" = 250000. \
        "1.5m" = 1500000. "2.5m" = 2500000. "5.73m" = 5730000. \
        Never round, never add extra zeros, never drop digits.
        Available main categories: \(Self.describe(categoryNames)).
        Available subcategories: \(Self.describe(subcategoryNames)).
        Category names are Indonesian; the meaning in parentheses tells you when to use them. \
        Output the exact category NAME (not the meaning). Choose ONLY from those lists; \
        leave empty if unsure.

        Examples:
        "buy meatballs 20k at the office canteen" -> amount 20000, type expense, daysAgo 0, \
        merchant "Office Canteen", note "meatballs", categoryName "Main Food"
        "pay electricity 350k yesterday" -> amount 350000, type expense, daysAgo 1, \
        note "electricity", categoryName "Tagihan"
        "salary came in 5.73m this month" -> amount 5730000, type income, daysAgo 0, categoryName "Gaji"
        "grab ride to the airport 125k" -> amount 125000, type expense, daysAgo 0, \
        merchant "Grab", note "ride to the airport", categoryName "Transport"
        "movie tickets 50k two days ago" -> amount 50000, type expense, daysAgo 2, note "movie", \
        categoryName "Lifestyle", subcategoryName "Hiburan"
        "swimming pool entry 60k" -> amount 60000, type expense, daysAgo 0, note "swimming", \
        categoryName "Lifestyle", subcategoryName "Olahraga"
        """
    }

    /// Glossary kategori seed: nama Indonesia + arti English agar model bisa
    /// memetakan input English → nama kategori Indonesia (BUG-1a).
    private static let glossary: [String: String] = [
        "Main Food": "daily meals",
        "Lifestyle": "leisure & hobbies",
        "Jajan": "snacks / street food / coffee",
        "Hiburan": "entertainment: movies, games, streaming, concerts",
        "Olahraga": "sports & fitness: gym membership, badminton, futsal, swimming, running gear",
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

    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "Perangkat ini tidak mendukung Apple Intelligence — gunakan input manual."
        case .appleIntelligenceNotEnabled:
            "Aktifkan Apple Intelligence di Settings untuk mencatat dengan kalimat."
        case .modelNotReady:
            "Model sedang disiapkan/diunduh. Coba lagi sebentar lagi."
        @unknown default:
            "Model tidak tersedia saat ini — gunakan input manual."
        }
    }
}
