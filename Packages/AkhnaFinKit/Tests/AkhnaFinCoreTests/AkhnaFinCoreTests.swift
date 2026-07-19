import Testing
import Foundation
@testable import AkhnaFinCore

@Suite("AkhnaFinCore — model & formatting")
struct AkhnaFinCoreTests {
    @Test("MoneyTransaction default sesuai baseline")
    func transactionDefaults() {
        let tx = MoneyTransaction()
        #expect(tx.amount == 0)
        #expect(tx.currencyCode == "IDR")
        #expect(tx.type == .expense)
        #expect(tx.source == .manual)
        #expect(tx.category == nil)
        #expect(tx.placeName.isEmpty)
    }

    @Test("TransactionCategory default & subkategori kosong")
    func categoryDefaults() {
        let c = TransactionCategory(name: "Main Food", isBuiltIn: true)
        #expect(c.name == "Main Food")
        #expect(c.kind == .expense)
        #expect(c.subcategories?.isEmpty == true)
        #expect(c.parent == nil)
    }

    @Test("TransactionType displayName Indonesia")
    func typeDisplayName() {
        #expect(TransactionType.expense.displayName == "Pengeluaran")
        #expect(TransactionType.income.displayName == "Pemasukan")
        #expect(TransactionType.transfer.displayName == "Transfer")
    }

    @Test("Format Rupiah locale id_ID")
    func currencyFormatting() {
        let s = CurrencyFormatter.string(from: 20000)
        #expect(s.contains("Rp"))
        #expect(s.contains("20"))
    }
}
