import Testing
import Foundation
import SwiftData
@testable import Persistence
import AkhnaFinCore
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

        let transaction = MoneyTransaction(amount: 20000, merchant: "Kantin")
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

    @Test("Kategori CRUD: tambah induk+sub, edit, hapus custom (transaksi ter-nullify)")
    func categoryCRUD() throws {
        let context = try makeContext()
        let repository = TransactionRepository(context: context)

        // Tambah induk + subkategori (mewarisi kind induk).
        let lifestyle = try repository.addCategory(name: "Hobi", iconName: "star", kind: .expense)
        let sub = try repository.addCategory(name: "Fotografi", kind: .income, parent: lifestyle)
        #expect(sub.parent?.name == "Hobi")
        #expect(sub.kind == .expense, "subkategori mewarisi kind induk, bukan argumen")
        #expect(try repository.fetchCategories().count == 2)

        // Edit.
        try repository.updateCategory(lifestyle, name: "Hobi & Seni", iconName: "paintbrush", colorHex: "#111")
        #expect(lifestyle.name == "Hobi & Seni")
        #expect(lifestyle.iconName == "paintbrush")

        // Transaksi menunjuk kategori custom → nullify saat kategori dihapus.
        let tx = MoneyTransaction(amount: 1000, category: sub)
        context.insert(tx)
        try context.save()
        try repository.deleteCategory(sub)
        #expect(tx.category == nil)
        #expect(try repository.fetchCategories().count == 1)
    }

    @Test("Kategori bawaan tak bisa dihapus; nama kosong ditolak")
    func categoryGuards() throws {
        let context = try makeContext()
        try CategorySeeder.seedIfNeeded(context: context)
        let repository = TransactionRepository(context: context)

        let builtIn = try #require(try repository.fetchCategories().first { $0.isBuiltIn })
        #expect(throws: TransactionRepository.CategoryError.builtInNotDeletable) {
            try repository.deleteCategory(builtIn)
        }
        #expect(throws: TransactionRepository.CategoryError.emptyName) {
            try repository.addCategory(name: "   ", kind: .expense)
        }
    }

    @Test("Gambar resi tersimpan saat commit; default nil")
    func commitAttachesReceiptImage() throws {
        let context = try makeContext()
        let repository = TransactionRepository(context: context)

        let image = Data([0x89, 0x50, 0x4E, 0x47])
        let withImage = try repository.commit(
            TransactionDraft(amount: 22200), source: .receipt, receiptImage: image
        )
        #expect(withImage.receiptImageData == image)
        #expect(withImage.source == .receipt)

        let without = try repository.commit(TransactionDraft(amount: 1000), source: .manual)
        #expect(without.receiptImageData == nil)
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

    @Test("Dedupe menggabungkan kategori dobel & memindahkan transaksinya")
    func dedupeMergesDuplicates() throws {
        let context = try makeContext()
        try CategorySeeder.seedIfNeeded(context: context)

        // Simulasi race seeding multi-device: set built-in kedua ter-import dari CloudKit.
        let duplicateMainFood = TransactionCategory(name: "Main Food", kind: .expense, isBuiltIn: true)
        context.insert(duplicateMainFood)
        let tx = MoneyTransaction(amount: 20000, category: duplicateMainFood)
        context.insert(tx)
        try context.save()

        try CategorySeeder.dedupeIfNeeded(context: context)

        let all = try context.fetch(FetchDescriptor<TransactionCategory>())
        #expect(all.filter { $0.name == "Main Food" }.count == 1)
        #expect(all.count == 10)
        // Transaksi milik duplikat berpindah ke kategori pemenang, bukan jadi nil.
        #expect(tx.category?.name == "Main Food")

        // Idempotent: run kedua tidak mengubah apa pun.
        try CategorySeeder.dedupeIfNeeded(context: context)
        #expect(try context.fetch(FetchDescriptor<TransactionCategory>()).count == 10)
    }

    @Test("Fetch per rentang tanggal")
    func fetchByDateInterval() throws {
        let context = try makeContext()
        let repository = TransactionRepository(context: context)
        let calendar = Calendar(identifier: .gregorian)

        let january15 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let february15 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        try repository.create(MoneyTransaction(amount: 10000, date: january15))
        try repository.create(MoneyTransaction(amount: 20000, date: february15))

        let january = DateInterval(
            start: calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        )
        let result = try repository.fetch(in: january)
        #expect(result.count == 1)
        #expect(result.first?.amount == 10000)
    }
}
