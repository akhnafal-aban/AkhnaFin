import Foundation

/// Jenis transaksi keuangan.
public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case transfer

    /// Label siap-tampil (satu sumber — dulu di-hardcode di snippet & form).
    public var displayName: String {
        switch self {
        case .expense: "Pengeluaran"
        case .income: "Pemasukan"
        case .transfer: "Transfer"
        }
    }
}
