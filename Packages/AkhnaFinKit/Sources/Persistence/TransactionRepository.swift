import Foundation
import OSLog
import SwiftData
import AkhnaFinCore
import ServiceInterfaces

private let persistenceSignposter = OSSignposter(subsystem: "com.aban.AkhnaFin", category: "Persistence")

/// Pintu tunggal operasi tulis/baca `MoneyTransaction` di atas `ModelContext`.
///
/// Read reaktif untuk UI tetap lewat `@Query` di View (MVVM hybrid); repository ini
/// dipakai ViewModel/intent untuk commit draft, CRUD, dan query non-reaktif.
@MainActor
public final class TransactionRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - CRUD

    public func create(_ transaction: MoneyTransaction) throws {
        context.insert(transaction)
        try context.save()
    }

    public func delete(_ transaction: MoneyTransaction) throws {
        context.delete(transaction)
        try context.save()
    }

    /// Simpan mutasi yang dilakukan langsung pada properti model.
    public func save() throws {
        try context.save()
    }

    public func fetchAll() throws -> [MoneyTransaction] {
        let descriptor = FetchDescriptor<MoneyTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func fetch(in interval: DateInterval) throws -> [MoneyTransaction] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Commit draft (muara pipeline capture)

    /// Ubah draft hasil parsing menjadi `MoneyTransaction` tersimpan;
    /// lokasi & gambar resi opsional ditempelkan di sini.
    @discardableResult
    public func commit(
        _ draft: TransactionDraft,
        source: EntrySource,
        place: CapturedPlace? = nil,
        receiptImage: Data? = nil
    ) throws -> MoneyTransaction {
        let interval = persistenceSignposter.beginInterval("commit")
        defer { persistenceSignposter.endInterval("commit", interval) }
        let transaction = MoneyTransaction(
            amount: draft.amount,
            currencyCode: draft.currencyCode,
            type: draft.type,
            date: draft.date,
            note: draft.note,
            merchant: draft.merchant,
            source: source,
            rawInput: draft.rawInput,
            category: try resolvedCategory(for: draft)
        )
        if let place {
            transaction.latitude = place.latitude
            transaction.longitude = place.longitude
            transaction.placeName = place.placeName
        }
        transaction.receiptImageData = receiptImage
        context.insert(transaction)
        try context.save()
        return transaction
    }

    // MARK: - Kategori CRUD

    public enum CategoryError: LocalizedError, Equatable {
        case builtInNotDeletable
        case emptyName

        public var errorDescription: String? {
            switch self {
            case .builtInNotDeletable: "Kategori bawaan tidak bisa dihapus."
            case .emptyName: "Nama kategori tidak boleh kosong."
            }
        }
    }

    public func fetchCategories() throws -> [TransactionCategory] {
        try context.fetch(FetchDescriptor<TransactionCategory>(
            sortBy: [SortDescriptor(\.name)]
        ))
    }

    @discardableResult
    public func addCategory(
        name: String,
        iconName: String = "tag",
        colorHex: String = "",
        kind: TransactionType,
        parent: TransactionCategory? = nil
    ) throws -> TransactionCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategoryError.emptyName }
        // Subkategori mewarisi jenis induknya (konsistensi hierarki).
        let category = TransactionCategory(
            name: trimmed, iconName: iconName, colorHex: colorHex,
            kind: parent?.kind ?? kind, isBuiltIn: false, parent: parent
        )
        context.insert(category)
        try context.save()
        return category
    }

    public func updateCategory(
        _ category: TransactionCategory,
        name: String,
        iconName: String,
        colorHex: String
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategoryError.emptyName }
        category.name = trimmed
        category.iconName = iconName
        category.colorHex = colorHex
        try context.save()
    }

    /// Hapus kategori CUSTOM. Bawaan dilindungi (seeder akan menambahkannya lagi →
    /// membingungkan). Transaksi & subkategori yang menunjuk ke sini ter-nullify
    /// otomatis (deleteRule .nullify di model) — subkategori jadi level teratas.
    public func deleteCategory(_ category: TransactionCategory) throws {
        guard !category.isBuiltIn else { throw CategoryError.builtInNotDeletable }
        context.delete(category)
        try context.save()
    }

    // MARK: - Resolusi kategori

    /// Subkategori diprioritaskan; bila tidak ketemu, jatuh ke kategori utama.
    private func resolvedCategory(for draft: TransactionDraft) throws -> TransactionCategory? {
        if !draft.subcategoryName.isEmpty,
           let sub = try resolveCategory(named: draft.subcategoryName, kind: draft.type) {
            return sub
        }
        return try resolveCategory(named: draft.categoryName, kind: draft.type)
    }

    /// Cari kategori dengan nama paling cocok: exact → prefix → contains
    /// (case/diacritic-insensitive), kandidat se-`kind` diprioritaskan.
    public func resolveCategory(named name: String, kind: TransactionType) throws -> TransactionCategory? {
        guard !name.isEmpty else { return nil }
        let all = try context.fetch(FetchDescriptor<TransactionCategory>())
        let sameKind = all.filter { $0.kind == kind }
        if let match = firstMatch(in: sameKind, target: name) { return match }
        return firstMatch(in: all, target: name)
    }

    private func firstMatch(in candidates: [TransactionCategory], target: String) -> TransactionCategory? {
        let target = normalize(target)
        if let exact = candidates.first(where: { normalize($0.name) == target }) {
            return exact
        }
        if let prefix = candidates.first(where: {
            let name = normalize($0.name)
            return name.hasPrefix(target) || target.hasPrefix(name)
        }) {
            return prefix
        }
        return candidates.first(where: {
            let name = normalize($0.name)
            return name.contains(target) || target.contains(name)
        })
    }

    private func normalize(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
