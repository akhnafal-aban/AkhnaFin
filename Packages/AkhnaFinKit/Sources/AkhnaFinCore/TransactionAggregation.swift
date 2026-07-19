import Foundation

/// Periode statistik dashboard. Dinamai `StatsPeriod` (bukan `Period`/`DateRange`)
/// menghindari bentrok tipe framework — pelajaran penamaan proyek ini.
public enum StatsPeriod: String, CaseIterable, Sendable {
    case week
    case month
    case year

    /// Label segmen UI.
    public var displayName: String {
        switch self {
        case .week: "Minggu"
        case .month: "Bulan"
        case .year: "Tahun"
        }
    }

    private var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// Interval periode yang memuat `date` (start inklusif, end eksklusif).
    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: date, duration: 0)
    }

    /// Geser interval `by` periode (negatif = mundur). Dihitung dari tanggal start
    /// agar batas bulan/tahun dengan panjang berbeda tetap benar.
    public func step(_ interval: DateInterval, by count: Int, calendar: Calendar = .current) -> DateInterval {
        guard let shifted = calendar.date(byAdding: component, value: count, to: interval.start) else {
            return interval
        }
        return self.interval(containing: shifted, calendar: calendar)
    }
}

/// Agregasi murni untuk dashboard — tanpa UI, tanpa SwiftData query; input array
/// transaksi (hasil `@Query` di View), output nilai siap-chart. Unit-testable.
public enum TransactionAggregation {
    /// Satu irisan donut kategori.
    public struct CategorySlice: Equatable, Sendable {
        public let name: String
        public let colorHex: String
        public let total: Decimal

        public init(name: String, colorHex: String, total: Decimal) {
            self.name = name
            self.colorHex = colorHex
            self.total = total
        }
    }

    /// Total pengeluaran & pemasukan. Transfer DIKECUALIKAN — perpindahan antar
    /// akun bukan arus keluar/masuk riil.
    public static func totals(_ transactions: [MoneyTransaction]) -> (expense: Decimal, income: Decimal) {
        transactions.reduce(into: (expense: Decimal(0), income: Decimal(0))) { acc, transaction in
            switch transaction.type {
            case .expense: acc.expense += transaction.amount
            case .income: acc.income += transaction.amount
            case .transfer: break
            }
        }
    }

    /// Pengeluaran per kategori INDUK (subkategori digulung ke induknya), terurut
    /// terbesar dulu. Tanpa kategori → bucket "Tanpa Kategori".
    public static func expenseByCategory(_ transactions: [MoneyTransaction]) -> [CategorySlice] {
        var totalsByName: [String: (colorHex: String, total: Decimal)] = [:]
        for transaction in transactions where transaction.type == .expense {
            let root = transaction.category.map { $0.parent ?? $0 }
            let name = root?.name ?? "Tanpa Kategori"
            let colorHex = root?.colorHex ?? ""
            totalsByName[name, default: (colorHex, 0)].total += transaction.amount
        }
        return totalsByName
            .map { CategorySlice(name: $0.key, colorHex: $0.value.colorHex, total: $0.value.total) }
            .sorted { $0.total > $1.total }
    }

    /// Pengeluaran per hari sepanjang `interval`, zero-filled (bar chart butuh
    /// hari kosong agar sumbu-x kontinu). Transaksi di luar interval diabaikan.
    public static func dailyExpenseSeries(
        _ transactions: [MoneyTransaction],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [(day: Date, total: Decimal)] {
        bucketedExpenseSeries(transactions, in: interval, unit: .day, calendar: calendar)
            .map { (day: $0.bucket, total: $0.total) }
    }

    /// Pengeluaran per bulan sepanjang `interval` — dipakai periode Tahun
    /// (365 bar harian tidak terbaca; 12 bar bulanan iya).
    public static func monthlyExpenseSeries(
        _ transactions: [MoneyTransaction],
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [(month: Date, total: Decimal)] {
        bucketedExpenseSeries(transactions, in: interval, unit: .month, calendar: calendar)
            .map { (month: $0.bucket, total: $0.total) }
    }

    /// Mesin bersama: kelompokkan expense ke awal bucket kalender, zero-filled.
    private static func bucketedExpenseSeries(
        _ transactions: [MoneyTransaction],
        in interval: DateInterval,
        unit: Calendar.Component,
        calendar: Calendar
    ) -> [(bucket: Date, total: Decimal)] {
        func bucketStart(_ date: Date) -> Date {
            calendar.dateInterval(of: unit, for: date)?.start ?? calendar.startOfDay(for: date)
        }

        var totalsByBucket: [Date: Decimal] = [:]
        for transaction in transactions
        where transaction.type == .expense && interval.contains(transaction.date) {
            totalsByBucket[bucketStart(transaction.date), default: 0] += transaction.amount
        }

        var series: [(bucket: Date, total: Decimal)] = []
        var bucket = bucketStart(interval.start)
        while bucket < interval.end {
            series.append((bucket: bucket, total: totalsByBucket[bucket] ?? 0))
            guard let next = calendar.date(byAdding: unit, value: 1, to: bucket) else { break }
            bucket = next
        }
        return series
    }
}
