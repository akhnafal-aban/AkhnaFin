import Testing
import Foundation
@testable import AkhnaFinCore

@Suite("DebtRecord — status turunan & summary")
struct DebtRecordTests {
    private func record(
        principal: Decimal,
        direction: DebtDirection = .iOwe,
        dueDate: Date? = nil,
        paid: [Decimal] = []
    ) -> DebtRecord {
        let record = DebtRecord(counterparty: "Test", direction: direction, principal: principal, dueDate: dueDate)
        record.payments = paid.map { DebtPayment(amount: $0) }
        return record
    }

    @Test("Tanpa pembayaran: sisa = pokok, belum lunas")
    func freshDebt() {
        let debt = record(principal: 100_000)
        #expect(debt.totalPaid == 0)
        #expect(debt.remaining == 100_000)
        #expect(!debt.isSettled)
    }

    @Test("Cicilan parsial mengurangi sisa")
    func partialPayment() {
        let debt = record(principal: 100_000, paid: [30_000, 20_000])
        #expect(debt.totalPaid == 50_000)
        #expect(debt.remaining == 50_000)
        #expect(!debt.isSettled)
    }

    @Test("Total cicilan = pokok → lunas")
    func settledExactly() {
        let debt = record(principal: 100_000, paid: [60_000, 40_000])
        #expect(debt.isSettled)
        #expect(debt.remaining == 0)
    }

    @Test("Overpay: sisa clamp 0, tetap lunas")
    func overpayClamped() {
        let debt = record(principal: 100_000, paid: [150_000])
        #expect(debt.remaining == 0)
        #expect(debt.isSettled)
    }

    @Test("Overdue: jatuh tempo lewat & belum lunas; lunas TIDAK overdue")
    func overdueRules() {
        let past = Date.now.addingTimeInterval(-86_400)
        let unpaid = record(principal: 50_000, dueDate: past)
        #expect(unpaid.isOverdue())
        let settled = record(principal: 50_000, dueDate: past, paid: [50_000])
        #expect(!settled.isOverdue())
        let noDue = record(principal: 50_000)
        #expect(!noDue.isOverdue())
    }

    @Test("Summary outstanding per arah — record lunas dilewati")
    func summaryOutstanding() {
        let records = [
            record(principal: 500_000, direction: .iOwe, paid: [200_000]),   // sisa 300k
            record(principal: 100_000, direction: .iOwe, paid: [100_000]),   // lunas → skip
            record(principal: 75_000, direction: .owedToMe),                  // sisa 75k
        ]
        let summary = DebtSummary.outstanding(records)
        #expect(summary.iOwe == 300_000)
        #expect(summary.owedToMe == 75_000)
    }
}
