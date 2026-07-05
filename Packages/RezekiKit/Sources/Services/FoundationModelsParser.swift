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
            amount: Self.rupiah(from: amount),
            type: TransactionType(rawValue: type) ?? .expense,
            date: date,
            note: note,
            merchant: merchant,
            categoryName: categoryName,
            subcategoryName: subcategoryName,
            rawInput: rawInput
        )
    }

    /// Double → Decimal dibulatkan 2 digit (hindari artefak floating-point), minimum 0.
    private static func rupiah(from amount: Double) -> Decimal {
        var value = Decimal(max(0, amount))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }
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
            let response = try await session.respond(to: text, generating: ParsedTransaction.self)
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

    private var instructions: String {
        """
        You are a personal-finance parser. Convert the user's English sentence into \
        structured transaction data. Amounts: "k" = thousand, "m" = million.
        Available main categories: \(categoryNames.joined(separator: ", ")).
        Available subcategories: \(subcategoryNames.joined(separator: ", ")).
        Choose categoryName/subcategoryName ONLY from those lists; leave empty if unsure.

        Examples:
        "buy meatballs 20k at the office canteen" -> amount 20000, type expense, daysAgo 0, \
        merchant "Office Canteen", note "meatballs", categoryName "Main Food"
        "pay electricity 350k yesterday" -> amount 350000, type expense, daysAgo 1, \
        note "electricity", categoryName "Tagihan"
        "salary came in 5.73m this month" -> amount 5370000, type income, daysAgo 0, categoryName "Gaji"
        "movie tickets 50k" -> amount 50000, type expense, daysAgo 0, note "movie", \
        categoryName "Lifestyle", subcategoryName "Hiburan"
        """
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
