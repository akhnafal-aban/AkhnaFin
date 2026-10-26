import Foundation
import SwiftData

@Model
public final class TransactionCategory {
    public var id: UUID = UUID()
    public var name: String = ""
    public var iconName: String = "tag"
    public var colorHex: String = ""
    public var kind: TransactionType = TransactionType.expense
    public var isBuiltIn: Bool = false

    public var parent: TransactionCategory?

    @Relationship(deleteRule: .nullify, inverse: \TransactionCategory.parent)
    public var subcategories: [TransactionCategory]? = []

    @Relationship(deleteRule: .nullify, inverse: \MoneyTransaction.category)
    public var transactions: [MoneyTransaction]? = []

    public init(
        id: UUID = UUID(),
        name: String = "",
        iconName: String = "tag",
        colorHex: String = "",
        kind: TransactionType = .expense,
        isBuiltIn: Bool = false,
        parent: TransactionCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.kind = kind
        self.isBuiltIn = isBuiltIn
        self.parent = parent
    }
}
