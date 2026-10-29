import Foundation

public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense
    case income
    case transfer

    public var displayName: LocalizedStringResource {
        switch self {
        case .expense: "Pengeluaran"
        case .income: "Pemasukan"
        case .transfer: "Transfer"
        }
    }
}
