import Testing
import Foundation
import RezekiCore
import ServiceInterfaces
@testable import Services

@Suite("Services — mapping ParsedTransaction → TransactionDraft")
struct ParsedTransactionMappingTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Calendar(identifier: .gregorian)
        .date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 20))!

    @Test("Field dasar ter-map & rawInput diteruskan")
    func basicMapping() {
        let parsed = ParsedTransaction(
            amount: 20000, type: "expense", daysAgo: 0,
            merchant: "Kantin Kantor", note: "bakso", categoryName: "Main Food"
        )
        let draft = parsed.draft(rawInput: "beli bakso 20k di kantin kantor", now: now, calendar: calendar)
        #expect(draft.amount == 20000)
        #expect(draft.type == .expense)
        #expect(draft.merchant == "Kantin Kantor")
        #expect(draft.note == "bakso")
        #expect(draft.categoryName == "Main Food")
        #expect(draft.rawInput == "beli bakso 20k di kantin kantor")
        #expect(calendar.isDate(draft.date, inSameDayAs: now))
    }

    @Test("daysAgo dihitung mundur; negatif di-clamp ke hari ini")
    func relativeDates() {
        let yesterday = ParsedTransaction(amount: 350000, type: "expense", daysAgo: 1)
            .draft(rawInput: "bayar listrik 350rb kemarin", now: now, calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(calendar.isDate(yesterday.date, inSameDayAs: expected))

        let future = ParsedTransaction(amount: 1000, type: "expense", daysAgo: -3)
            .draft(rawInput: "x", now: now, calendar: calendar)
        #expect(calendar.isDate(future.date, inSameDayAs: now))
    }

    @Test("Type income/transfer ter-map; nilai tak dikenal jatuh ke expense")
    func typeMapping() {
        #expect(ParsedTransaction(amount: 8_000_000, type: "income", daysAgo: 0)
            .draft(rawInput: "gaji masuk 8jt").type == .income)
        #expect(ParsedTransaction(amount: 100, type: "transfer", daysAgo: 0)
            .draft(rawInput: "x").type == .transfer)
        #expect(ParsedTransaction(amount: 100, type: "belanja", daysAgo: 0)
            .draft(rawInput: "x").type == .expense)
    }

    @Test("Amount negatif di-clamp 0; artefak floating point dibulatkan")
    func amountSanitization() {
        #expect(ParsedTransaction(amount: -500, type: "expense", daysAgo: 0)
            .draft(rawInput: "x").amount == 0)
        let draft = ParsedTransaction(amount: 20000.004, type: "expense", daysAgo: 0)
            .draft(rawInput: "x")
        #expect(draft.amount == 20000)
    }

    @Test("Parser unavailable melempar TransactionParsingError.modelUnavailable")
    func unavailableThrows() async {
        let parser = FoundationModelsParser(categoryNames: [], subcategoryNames: [])
        guard case .unavailable = parser.availability else {
            // Host test punya Apple Intelligence aktif — jalur unavailable tak bisa diuji di sini.
            return
        }
        await #expect(throws: TransactionParsingError.self) {
            _ = try await parser.parse("beli bakso 20k")
        }
    }
}
