import Foundation
import SwiftData

@Model
public final class MoneyTransaction {
    public var id: UUID = UUID()
    public var amount: Decimal = 0
    public var currencyCode: String = "IDR"
    public var type: TransactionType = TransactionType.expense
    public var date: Date = Date.now
    public var note: String = ""
    public var merchant: String = ""
    public var source: EntrySource = EntrySource.manual
    public var rawInput: String = ""
    public var createdAt: Date = Date.now

    // MARK: Lokasi (ditangkap otomatis-senyap saat commit)
    public var latitude: Double?
    public var longitude: Double?
    public var placeName: String = ""

    @Attribute(.externalStorage)
    public var receiptImageData: Data?

    public var category: TransactionCategory?

    public init(
        id: UUID = UUID(),
        amount: Decimal = 0,
        currencyCode: String = "IDR",
        type: TransactionType = .expense,
        date: Date = .now,
        note: String = "",
        merchant: String = "",
        source: EntrySource = .manual,
        rawInput: String = "",
        createdAt: Date = .now,
        category: TransactionCategory? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.type = type
        self.date = date
        self.note = note
        self.merchant = merchant
        self.source = source
        self.rawInput = rawInput
        self.createdAt = createdAt
        self.category = category
    }
}
