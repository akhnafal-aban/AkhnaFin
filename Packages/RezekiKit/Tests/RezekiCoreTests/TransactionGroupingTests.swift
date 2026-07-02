import Testing
import Foundation
@testable import RezekiCore

@Suite("RezekiCore — grouping transaksi")
struct TransactionGroupingTests {
    @Test("Grup per hari, terbaru dulu, item dalam hari terurut menurun")
    func groupsByDayNewestFirst() {
        let calendar = Calendar(identifier: .gregorian)
        func date(_ day: Int, hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
        }

        let morning = MoneyTransaction(amount: 10000, date: date(1, hour: 8))
        let evening = MoneyTransaction(amount: 20000, date: date(1, hour: 19))
        let nextDay = MoneyTransaction(amount: 30000, date: date(2, hour: 12))

        let groups = TransactionGrouping.groupByDay([morning, evening, nextDay], calendar: calendar)

        #expect(groups.count == 2)
        #expect(groups[0].day > groups[1].day)
        #expect(groups[0].items.map(\.amount) == [30000])
        #expect(groups[1].items.map(\.amount) == [20000, 10000])
    }

    @Test("Daftar kosong menghasilkan grup kosong")
    func emptyInput() {
        #expect(TransactionGrouping.groupByDay([]).isEmpty)
    }
}
