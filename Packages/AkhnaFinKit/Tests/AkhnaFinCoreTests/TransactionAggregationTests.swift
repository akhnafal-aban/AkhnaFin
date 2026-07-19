import Testing
import Foundation
@testable import AkhnaFinCore

/// Kalender deterministik untuk test: locale id_ID (Senin awal minggu), zona WIB.
private func idCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "id_ID")
    calendar.firstWeekday = 2  // Senin — eksplisit agar test tak bergantung environment
    calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    return calendar
}

private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    idCalendar().date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

private func tx(
    _ amount: Decimal,
    type: TransactionType = .expense,
    date: Date = date(2026, 7, 15),
    category: TransactionCategory? = nil
) -> MoneyTransaction {
    MoneyTransaction(amount: amount, type: type, date: date, category: category)
}

@Suite("StatsPeriod — interval & stepping")
struct StatsPeriodTests {
    let calendar = idCalendar()

    @Test("Interval minggu: Senin 00:00 s.d. Senin berikutnya (id_ID)")
    func weekInterval() {
        // 15 Jul 2026 = Rabu → minggu berjalan Senin 13 Jul s.d. Senin 20 Jul.
        let interval = StatsPeriod.week.interval(containing: date(2026, 7, 15), calendar: calendar)
        #expect(interval.start == date(2026, 7, 13, hour: 0))
        #expect(interval.end == date(2026, 7, 20, hour: 0))
    }

    @Test("Interval bulan: tanggal 1 s.d. tanggal 1 bulan berikutnya")
    func monthInterval() {
        let interval = StatsPeriod.month.interval(containing: date(2026, 7, 15), calendar: calendar)
        #expect(interval.start == date(2026, 7, 1, hour: 0))
        #expect(interval.end == date(2026, 8, 1, hour: 0))
    }

    @Test("Interval tahun: 1 Jan s.d. 1 Jan tahun berikutnya")
    func yearInterval() {
        let interval = StatsPeriod.year.interval(containing: date(2026, 7, 15), calendar: calendar)
        #expect(interval.start == date(2026, 1, 1, hour: 0))
        #expect(interval.end == date(2027, 1, 1, hour: 0))
    }

    @Test("Stepping mundur satu bulan mendarat di bulan sebelumnya")
    func stepBackMonth() {
        let july = StatsPeriod.month.interval(containing: date(2026, 7, 15), calendar: calendar)
        let june = StatsPeriod.month.step(july, by: -1, calendar: calendar)
        #expect(june.start == date(2026, 6, 1, hour: 0))
        #expect(june.end == date(2026, 7, 1, hour: 0))
    }

    @Test("Stepping maju melewati batas tahun")
    func stepForwardAcrossYear() {
        let december = StatsPeriod.month.interval(containing: date(2026, 12, 10), calendar: calendar)
        let january = StatsPeriod.month.step(december, by: 1, calendar: calendar)
        #expect(january.start == date(2027, 1, 1, hour: 0))
    }
}

@Suite("TransactionAggregation — totals, kategori, seri harian")
struct TransactionAggregationTests {
    let calendar = idCalendar()

    @Test("Totals: expense & income terpisah, transfer DIKECUALIKAN")
    func totalsExcludeTransfer() {
        let transactions = [
            tx(20000), tx(30000),
            tx(5_000_000, type: .income),
            tx(1_000_000, type: .transfer),
        ]
        let totals = TransactionAggregation.totals(transactions)
        #expect(totals.expense == 50000)
        #expect(totals.income == 5_000_000)
    }

    @Test("Totals dari daftar kosong = nol")
    func totalsEmpty() {
        let totals = TransactionAggregation.totals([])
        #expect(totals.expense == 0)
        #expect(totals.income == 0)
    }

    @Test("Breakdown kategori: subkategori digulung ke induk, sorted desc")
    func categoryRollUp() {
        let lifestyle = TransactionCategory(name: "Lifestyle", colorHex: "#AABBCC")
        let jajan = TransactionCategory(name: "Jajan", parent: lifestyle)
        let food = TransactionCategory(name: "Main Food", colorHex: "#112233")
        let transactions = [
            tx(10000, category: jajan),        // → Lifestyle
            tx(15000, category: lifestyle),    // → Lifestyle (total 25000)
            tx(20000, category: food),
        ]
        let slices = TransactionAggregation.expenseByCategory(transactions)
        #expect(slices.count == 2)
        #expect(slices[0].name == "Lifestyle")
        #expect(slices[0].total == 25000)
        #expect(slices[0].colorHex == "#AABBCC")
        #expect(slices[1].name == "Main Food")
        #expect(slices[1].total == 20000)
    }

    @Test("Tanpa kategori → bucket \"Tanpa Kategori\"; income tak ikut")
    func uncategorizedBucketAndExpenseOnly() {
        let transactions = [
            tx(7000),
            tx(9_000_000, type: .income),  // bukan expense — harus diabaikan
        ]
        let slices = TransactionAggregation.expenseByCategory(transactions)
        #expect(slices.count == 1)
        #expect(slices[0].name == "Tanpa Kategori")
        #expect(slices[0].total == 7000)
    }

    @Test("Seri harian: zero-filled sepanjang interval, hanya expense")
    func dailySeriesZeroFilled() {
        let week = StatsPeriod.week.interval(containing: date(2026, 7, 15), calendar: calendar)
        let transactions = [
            tx(10000, date: date(2026, 7, 13)),
            tx(5000, date: date(2026, 7, 13)),   // hari sama → dijumlah
            tx(20000, date: date(2026, 7, 16)),
            tx(999_999, type: .income, date: date(2026, 7, 14)),  // income diabaikan
            tx(888_888, date: date(2026, 7, 25)),  // di luar interval → diabaikan
        ]
        let series = TransactionAggregation.dailyExpenseSeries(transactions, in: week, calendar: calendar)
        #expect(series.count == 7)
        #expect(series[0].day == date(2026, 7, 13, hour: 0))
        #expect(series[0].total == 15000)
        #expect(series[1].total == 0)   // 14 Jul: income saja → 0
        #expect(series[3].total == 20000)
        #expect(series.map(\.total).reduce(0, +) == 35000)
    }

    @Test("Seri bulanan: 12 bucket zero-filled untuk periode tahun")
    func monthlySeriesForYear() {
        let year = StatsPeriod.year.interval(containing: date(2026, 7, 15), calendar: calendar)
        let transactions = [
            tx(100_000, date: date(2026, 1, 5)),
            tx(50_000, date: date(2026, 1, 20)),   // bulan sama → dijumlah
            tx(75_000, date: date(2026, 7, 15)),
        ]
        let series = TransactionAggregation.monthlyExpenseSeries(transactions, in: year, calendar: calendar)
        #expect(series.count == 12)
        #expect(series[0].month == date(2026, 1, 1, hour: 0))
        #expect(series[0].total == 150_000)
        #expect(series[1].total == 0)
        #expect(series[6].total == 75_000)
    }
}
