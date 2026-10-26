import Foundation
import SwiftData
import AkhnaFinCore

@MainActor
public final class DebtRepository {
    public enum DebtError: LocalizedError, Equatable {
        case emptyCounterparty
        case nonPositiveAmount

        public var errorDescription: String? {
            switch self {
            case .emptyCounterparty: "Nama pihak tidak boleh kosong."
            case .nonPositiveAmount: "Nominal harus lebih dari nol."
            }
        }
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - CRUD

    @discardableResult
    public func create(
        counterparty: String,
        direction: DebtDirection,
        principal: Decimal,
        note: String = "",
        dueDate: Date? = nil
    ) throws -> DebtRecord {
        let trimmed = counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DebtError.emptyCounterparty }
        guard principal > 0 else { throw DebtError.nonPositiveAmount }
        let record = DebtRecord(
            counterparty: trimmed, direction: direction,
            principal: principal, note: note, dueDate: dueDate
        )
        context.insert(record)
        try context.save()
        return record
    }

    public func delete(_ record: DebtRecord) throws {
        context.delete(record)  // payments ikut (cascade)
        try context.save()
    }

    public func save() throws {
        try context.save()
    }

    public func fetchAll(now: Date = .now) throws -> [DebtRecord] {
        let all = try context.fetch(FetchDescriptor<DebtRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        return DebtRecord.openFirstSorted(all, now: now)
    }

    // MARK: - Cicilan

    @discardableResult
    public func addPayment(
        _ amount: Decimal,
        to record: DebtRecord,
        date: Date = .now,
        note: String = ""
    ) throws -> DebtPayment {
        guard amount > 0 else { throw DebtError.nonPositiveAmount }
        let payment = DebtPayment(amount: amount, date: date, note: note)
        payment.debt = record
        context.insert(payment)
        try context.save()
        return payment
    }

    public func settle(_ record: DebtRecord, date: Date = .now) throws {
        guard !record.isSettled else { return }
        try addPayment(record.remaining, to: record, date: date, note: "Pelunasan")
    }
}
