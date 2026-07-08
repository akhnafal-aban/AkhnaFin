import SwiftUI
import RezekiCore

/// Satu baris transaksi di daftar: ikon kategori, judul, tempat, dan nominal.
struct TransactionRow: View {
    private let transaction: MoneyTransaction

    init(_ transaction: MoneyTransaction) {
        self.transaction = transaction
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.iconName ?? "tag")
                .font(.body)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(formattedAmount)
                .font(.callout.monospacedDigit())
                .foregroundStyle(transaction.type == .income ? .green : .primary)
        }
    }

    private var title: String {
        if !transaction.merchant.isEmpty { return transaction.merchant }
        if !transaction.note.isEmpty { return transaction.note }
        return transaction.category?.name ?? "Transaksi"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let name = transaction.category?.name { parts.append(name) }
        if !transaction.placeName.isEmpty { parts.append(transaction.placeName) }
        return parts.joined(separator: " • ")
    }

    private var formattedAmount: String {
        let amount = CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.currencyCode)
        return transaction.type == .income ? "+\(amount)" : amount
    }
}
