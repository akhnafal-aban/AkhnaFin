import Foundation
import AkhnaFinCore

/// Draft transaksi yang mengalir di pipeline `parse → draft (editable) → confirm → save`.
///
/// Tipe polos tanpa dependensi framework AI — implementasi parser (mis. Foundation
/// Models dengan `@Generable`) hidup di target `Services` dan me-map hasilnya ke sini.
public struct TransactionDraft: Sendable, Equatable, Codable {
    public var amount: Decimal
    public var currencyCode: String
    public var type: TransactionType
    public var date: Date
    public var note: String
    public var merchant: String
    public var categoryName: String
    public var subcategoryName: String
    public var rawInput: String

    /// Talangan: dibayari dulu untuk orang lain.
    /// Parser bisa set ini dari kalimat ("talangin budi 50k").
    public var isReimbursable: Bool = false
    public var reimbursedBy: String = ""

    public init(
        amount: Decimal = 0,
        currencyCode: String = "IDR",
        type: TransactionType = .expense,
        date: Date = .now,
        note: String = "",
        merchant: String = "",
        categoryName: String = "",
        subcategoryName: String = "",
        rawInput: String = "",
        isReimbursable: Bool = false,
        reimbursedBy: String = ""
    ) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.type = type
        self.date = date
        self.note = note
        self.merchant = merchant
        self.categoryName = categoryName
        self.subcategoryName = subcategoryName
        self.rawInput = rawInput
        self.isReimbursable = isReimbursable
        self.reimbursedBy = reimbursedBy
    }
}
