import Testing
import Foundation
import SwiftData
@testable import Persistence
import RezekiCore
import ServiceInterfaces

@MainActor
@Suite("Persistence — seeder, repository, draft mapping")
struct PersistenceTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.make(mode: .inMemory))
    }

    @Test("Seeder idempotent & hierarki subkategori benar")
    func seederIdempotentWithHierarchy() throws {
        let context = try makeContext()
        try CategorySeeder.seedIfNeeded(context: context)
        try CategorySeeder.seedIfNeeded(context: context) // run kedua tidak menduplikasi

        let all = try context.fetch(FetchDescriptor<TransactionCategory>())
        #expect(all.count == 10)
        #expect(all.filter { $0.parent == nil }.count == 7)
        #expect(all.filter { $0.kind == .income }.map(\.name).sorted() == ["Bonus", "Gaji"])

        let lifestyle = all.first { $0.name == "Lifestyle" }
        #expect(lifestyle?.subcategories?.count == 3)
        let jajan = all.first { $0.name == "Jajan" }
        #expect(jajan?.parent?.name == "Lifestyle")
    }

    @Test("CRUD repository")
    func repositoryCRUD() throws {
        let context = try makeContext()
        let repository = TransactionRepository(context: context)

        let transaction = Transaction(amount: 20000, merchant: "Kantin")
        try repository.create(transaction)
        #expect(try repository.fetchAll().count == 1)

        transaction.amount = 25000
        try repository.save()
        #expect(try repository.fetchAll().first?.amount == 25000)

        try repository.delete(transaction)
        #expect(try repository.fetchAll().isEmpty)
    }

    @Test("Commit draft me-resolve kategori & subkategori")
    func commitResolvesCategories() throws {
        let context = try makeContext()
        try CategorySeeder.seedIfNeeded(context: context)
        let repository = TransactionRepository(context: context)

        let draft = TransactionDraft(
            amount: 20000,
            merchant: "Kantin Kantor",
            categoryName: "main food",
            rawInput: "beli bakso 20k di kantin kantor"
        )
        let tx = try repository.commit(draft, source: .appIntent)
        #expect(tx.category?.name == "Main Food")
        #expect(tx.source == .appIntent)
        #expect(tx.rawInput == "beli bakso 20k di kantin kantor")

        let subDraft = TransactionDraft(amount: 50000, categoryName: "Lifestyle", subcategoryName: "Jajan")
        #expect(try repository.commit(subDraft, source: .batch).category?.name == "Jajan")

        let incomeDraft = TransactionDraft(amount: 8_000_000, type: .income, categoryName: "Gaji")
        #expect(try repository.commit(incomeDraft, source: .voice).category?.name == "Gaji")

        let missDraft = TransactionDraft(amount: 1000, categoryName: "Belanja Online")
        #expect(try repository.commit(missDraft, source: .manual).category == nil)
    }

    @Test("Lokasi dari CapturedPlace tersimpan di transaksi")
    func commitAttachesPlace() throws {
        let context = try makeContext()
        let repository = TransactionRepository(context: context)

        let place = CapturedPlace(latitude: -6.1754, longitude: 106.8272, placeName: "Kantin Kantor")
        let tx = try repository.commit(TransactionDraft(amount: 20000), source: .voice, place: place)
        #expect(tx.latitude == -6.1754)
        #expect(tx.longitude == 106.8272)
        #expect(tx.placeName == "Kantin Kantor")
    }

    @Test("Fetch per rentang tanggal")
    func fetchByDateInterval() throws {
        let context = try makeContext()
        let repository = TransactionRepository(context: context)
        let calendar = Calendar(identifier: .gregorian)

        let january15 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let february15 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        try repository.create(Transaction(amount: 10000, date: january15))
        try repository.create(Transaction(amount: 20000, date: february15))

        let january = DateInterval(
            start: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        )
        let result = try repository.fetch(in: january)
        #expect(result.count == 1)
        #expect(result.first?.amount == 10000)
    }
}
