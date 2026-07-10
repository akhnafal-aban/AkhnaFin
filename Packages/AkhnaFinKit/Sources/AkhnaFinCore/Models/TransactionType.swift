import Foundation

/// Jenis transaksi keuangan.
public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case transfer
}
