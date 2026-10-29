import SwiftUI
import AkhnaFinCore

struct TransactionRow: View {
    private let transaction: MoneyTransaction

    init(_ transaction: MoneyTransaction) {
        self.transaction = transaction
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category?.iconName ?? "tag")
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconBackground, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
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
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(transaction.type == .income ? AppTheme.lime : AppTheme.ink)
        }
    }

    private var iconColor: Color {
        guard let hex = transaction.category?.colorHex, !hex.isEmpty else { return .secondary }
        return Color(hex: hex)
    }

    private var iconBackground: Color {
        guard let hex = transaction.category?.colorHex, !hex.isEmpty else { return Color(.systemGray4).opacity(0.4) }
        return Color(hex: hex).opacity(0.16)
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