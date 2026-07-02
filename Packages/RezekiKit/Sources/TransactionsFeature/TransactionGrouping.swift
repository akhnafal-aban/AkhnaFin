import Foundation
import RezekiCore

/// Pengelompokan transaksi per hari untuk section daftar (baseline iOS 26 —
/// diganti SwiftData sectioned fetch saat adopsi iOS 27).
public enum TransactionGrouping {
    public static func groupByDay(
        _ transactions: [MoneyTransaction],
        calendar: Calendar = .current
    ) -> [(day: Date, items: [MoneyTransaction])] {
        let groups = Dictionary(grouping: transactions) { calendar.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            (day: day, items: groups[day]!.sorted { $0.date > $1.date })
        }
    }
}
