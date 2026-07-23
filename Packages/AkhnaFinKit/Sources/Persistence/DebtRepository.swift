import Foundation
import OSLog
import SwiftData
import AkhnaFinCore

/// Log kategori `Persistence` (sejajar `TransactionRepository`). Nama pihak =
/// PII → dibiarkan default (interpolasi Logger meredaksi di Release); arah &
/// nominal `.public` untuk diagnosis.
private let debtLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Persistence")

/// Pintu tunggal operasi `DebtRecord` di atas `ModelContext` — pola yang sama
/// dengan `TransactionRepository`. Read reaktif UI tetap via `@Query`.
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
        debtLog.info("debt create: \(direction.rawValue, privacy: .public) principal=\(principal, privacy: .public) pihak=\(trimmed)")
        return record
    }

    public func delete(_ record: DebtRecord) throws {
        let direction = record.direction.rawValue
        context.delete(record)  // payments ikut (cascade)
        try context.save()
        debtLog.info("debt delete: \(direction, privacy: .public)")
    }

    /// Simpan mutasi langsung pada properti model (jalur edit).
    public func save() throws {
        try context.save()
    }

    /// Semua record; belum lunas dulu (terlambat paling atas), lalu yang lunas.
    /// Sort di memory — status lunas dihitung, tak bisa masuk predicate.
    public func fetchAll(now: Date = .now) throws -> [DebtRecord] {
        let all = try context.fetch(FetchDescriptor<DebtRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let open = all.filter { !$0.isSettled }
            .sorted { lhs, rhs in
                switch (lhs.isOverdue(now: now), rhs.isOverdue(now: now)) {
                case (true, false): true
                case (false, true): false
                default: (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
                }
            }
        return open + all.filter(\.isSettled)
    }

    // MARK: - Cicilan

    /// Catat satu cicilan. Nominal wajib > 0; boleh melebihi sisa (overpay
    /// di-clamp di `remaining`, kejadian nyata: bayar bulat).
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
        debtLog.info("debt payment: \(amount, privacy: .public) sisa=\(record.remaining, privacy: .public) lunas=\(record.isSettled, privacy: .public)")
        return payment
    }

    /// Lunasi = tambah pembayaran sebesar SISA (satu mekanisme dengan cicilan).
    /// No-op bila sudah lunas.
    public func settle(_ record: DebtRecord, date: Date = .now) throws {
        guard !record.isSettled else { return }
        try addPayment(record.remaining, to: record, date: date, note: "Pelunasan")
    }
}
