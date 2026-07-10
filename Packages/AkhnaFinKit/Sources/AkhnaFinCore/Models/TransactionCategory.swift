import Foundation
import SwiftData

/// Kategori transaksi, mendukung subkategori lewat relasi self-referential.
///
/// Dinamai `TransactionCategory` (bukan `Category`) untuk menghindari bentrok dengan
/// typedef `Category` milik Objective-C runtime saat dipakai lintas modul.
///
/// CloudKit-compatible: setiap atribut punya default value, semua relasi optional
/// dengan inverse, dan tidak ada `@Attribute(.unique)`.
@Model
public final class TransactionCategory {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Nama SF Symbol untuk ikon kategori.
    public var iconName: String = "tag"
    public var colorHex: String = ""
    public var kind: TransactionType = TransactionType.expense
    public var isBuiltIn: Bool = false

    /// Kategori induk (nil untuk kategori level teratas).
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
