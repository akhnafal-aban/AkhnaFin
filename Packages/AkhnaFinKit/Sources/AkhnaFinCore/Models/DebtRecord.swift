import Foundation
import SwiftData

/// Arah hutang dari sudut pandang pemilik app.
public enum DebtDirection: String, Codable, CaseIterable, Sendable {
    /// Aku yang berutang (ke teman ATAU platform paylater).
    case iOwe
    /// Orang lain berutang ke aku (piutang).
    case owedToMe

    public var displayName: String {
        switch self {
        case .iOwe: "Aku Berutang"
        case .owedToMe: "Berutang ke Aku"
        }
    }
}

/// Satu catatan hutang/piutang — LEDGER TERPISAH dari kas (keputusan PLAN-005):
/// tidak pernah otomatis membuat `MoneyTransaction`.
///
/// `counterparty` teks bebas: nama orang ("Budi") atau platform paylater
/// ("SPayLater", "GoPayLater"). Status lunas DIHITUNG dari pembayaran, bukan
/// disimpan — tak ada flag yang bisa desinkron.
///
/// CloudKit-compatible: semua atribut punya default/optional, relasi optional
/// dengan inverse, tanpa `@Attribute(.unique)`.
@Model
public final class DebtRecord {
    public var id: UUID = UUID()
    public var counterparty: String = ""
    public var direction: DebtDirection = DebtDirection.iOwe
    /// Pokok hutang (nominal awal yang dipinjam).
    public var principal: Decimal = 0
    public var currencyCode: String = "IDR"
    public var note: String = ""
    public var createdAt: Date = Date.now
    /// Jatuh tempo opsional (tanpa notifikasi — fase nanti).
    public var dueDate: Date?

    /// Cicilan pembayaran. Hapus record → pembayaran ikut terhapus.
    @Relationship(deleteRule: .cascade, inverse: \DebtPayment.debt)
    public var payments: [DebtPayment]? = []

    public init(
        id: UUID = UUID(),
        counterparty: String = "",
        direction: DebtDirection = .iOwe,
        principal: Decimal = 0,
        currencyCode: String = "IDR",
        note: String = "",
        createdAt: Date = .now,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.counterparty = counterparty
        self.direction = direction
        self.principal = principal
        self.currencyCode = currencyCode
        self.note = note
        self.createdAt = createdAt
        self.dueDate = dueDate
    }
}

/// Satu cicilan pembayaran atas sebuah `DebtRecord`.
@Model
public final class DebtPayment {
    public var id: UUID = UUID()
    public var amount: Decimal = 0
    public var date: Date = Date.now
    public var note: String = ""

    /// Induk (inverse didefinisikan di `DebtRecord.payments`). CloudKit: optional.
    public var debt: DebtRecord?

    public init(
        id: UUID = UUID(),
        amount: Decimal = 0,
        date: Date = .now,
        note: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
    }
}

// MARK: - Status turunan (dihitung, bukan disimpan)

extension DebtRecord {
    /// Total semua cicilan yang sudah dibayar.
    public var totalPaid: Decimal {
        (payments ?? []).reduce(0) { $0 + $1.amount }
    }

    /// Sisa hutang, clamp ≥ 0 (overpay tidak membuat sisa negatif).
    public var remaining: Decimal {
        max(0, principal - totalPaid)
    }

    public var isSettled: Bool {
        remaining <= 0
    }

    /// Terlambat = jatuh tempo lewat DAN belum lunas.
    public func isOverdue(now: Date = .now) -> Bool {
        guard let dueDate, !isSettled else { return false }
        return dueDate < now
    }
}

/// Agregasi murni untuk kartu Dashboard.
public enum DebtSummary {
    /// Total SISA (outstanding) per arah — record lunas tidak dihitung.
    public static func outstanding(_ records: [DebtRecord]) -> (iOwe: Decimal, owedToMe: Decimal) {
        records.reduce(into: (iOwe: Decimal(0), owedToMe: Decimal(0))) { acc, record in
            guard !record.isSettled else { return }
            switch record.direction {
            case .iOwe: acc.iOwe += record.remaining
            case .owedToMe: acc.owedToMe += record.remaining
            }
        }
    }
}
