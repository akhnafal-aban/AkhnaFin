import Foundation
import SwiftData
import RezekiCore
import ServiceInterfaces

/// Pintu tunggal operasi tulis/baca `Transaction` di atas `ModelContext`.
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

    public func create(_ transaction: Transaction) throws {
        context.insert(transaction)
        try context.save()
    }

    public func delete(_ transaction: Transaction) throws {
        context.delete(transaction)
        try context.save()
    }

    /// Simpan mutasi yang dilakukan langsung pada properti model.
    public func save() throws {
        try context.save()
    }

    public func fetchAll() throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    public func fetch(in interval: DateInterval) throws -> [Transaction] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Commit draft (muara pipeline capture)

    /// Ubah draft hasil parsing menjadi `Transaction` tersimpan; lokasi opsional ditempelkan di sini.
    @discardableResult
    public func commit(
        _ draft: TransactionDraft,
        source: EntrySource,
        place: CapturedPlace? = nil
    ) throws -> Transaction {
        let transaction = Transaction(
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
        context.insert(transaction)
        try context.save()
        return transaction
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
