import Testing
import Foundation
import SwiftData
@testable import Persistence
import AkhnaFinCore

@MainActor
@Suite("DebtRepository — CRUD, cicilan, pelunasan")
struct DebtRepositoryTests {
    private func makeRepository() throws -> DebtRepository {
        DebtRepository(context: ModelContext(try ModelContainerFactory.make(mode: .inMemory)))
    }

    @Test("Create memvalidasi counterparty & nominal")
    func createValidation() throws {
        let repository = try makeRepository()
        #expect(throws: DebtRepository.DebtError.emptyCounterparty) {
            try repository.create(counterparty: "  ", direction: .iOwe, principal: 1000)
        }
        #expect(throws: DebtRepository.DebtError.nonPositiveAmount) {
            try repository.create(counterparty: "SPayLater", direction: .iOwe, principal: 0)
        }
        let record = try repository.create(counterparty: " Budi ", direction: .owedToMe, principal: 50_000)
        #expect(record.counterparty == "Budi")  // trimmed
        #expect(try repository.fetchAll().count == 1)
    }

    @Test("addPayment menambah cicilan; nominal ≤ 0 ditolak")
    func addPayment() throws {
        let repository = try makeRepository()
        let record = try repository.create(counterparty: "GoPayLater", direction: .iOwe, principal: 300_000)
        try repository.addPayment(100_000, to: record)
        try repository.addPayment(50_000, to: record)
        #expect(record.totalPaid == 150_000)
        #expect(record.remaining == 150_000)
        #expect(throws: DebtRepository.DebtError.nonPositiveAmount) {
            try repository.addPayment(0, to: record)
        }
    }

    @Test("settle membayar sisa persis; idempotent saat sudah lunas")
    func settleIdempotent() throws {
        let repository = try makeRepository()
        let record = try repository.create(counterparty: "Budi", direction: .owedToMe, principal: 200_000)
        try repository.addPayment(80_000, to: record)
        try repository.settle(record)
        #expect(record.isSettled)
        #expect(record.totalPaid == 200_000)
        let paymentCount = record.payments?.count
        try repository.settle(record)  // no-op
        #expect(record.payments?.count == paymentCount)
    }

    @Test("Hapus record menghapus payments (cascade)")
    func cascadeDelete() throws {
        let repository = try makeRepository()
        let record = try repository.create(counterparty: "Budi", direction: .iOwe, principal: 100_000)
        try repository.addPayment(40_000, to: record)
        let context = record.modelContext!
        try repository.delete(record)
        #expect(try context.fetch(FetchDescriptor<DebtRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DebtPayment>()).isEmpty)
    }

    @Test("fetchAll: terlambat dulu → jatuh tempo terdekat → lunas terakhir")
    func fetchAllOrdering() throws {
        let repository = try makeRepository()
        let now = Date.now
        let settled = try repository.create(counterparty: "Lunas", direction: .iOwe, principal: 10_000)
        try repository.settle(settled)
        let dueSoon = try repository.create(
            counterparty: "DueSoon", direction: .iOwe, principal: 20_000,
            dueDate: now.addingTimeInterval(86_400)
        )
        let overdue = try repository.create(
            counterparty: "Overdue", direction: .iOwe, principal: 30_000,
            dueDate: now.addingTimeInterval(-86_400)
        )
        let ordered = try repository.fetchAll(now: now)
        #expect(ordered.map(\.counterparty) == ["Overdue", "DueSoon", "Lunas"])
        _ = (dueSoon, overdue)
    }
}
