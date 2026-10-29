import Foundation
import SwiftData

public enum DebtDirection: String, Codable, CaseIterable, Sendable {
    case iOwe
    case owedToMe

    public var displayName: LocalizedStringResource {
        switch self {
        case .iOwe: "Aku Berutang"
        case .owedToMe: "Berutang ke Aku"
        }
    }
}

@Model
public final class DebtRecord {
    public var id: UUID = UUID()
    public var counterparty: String = ""
    public var direction: DebtDirection = DebtDirection.iOwe
    public var principal: Decimal = 0
    public var currencyCode: String = "IDR"
    public var note: String = ""
    public var createdAt: Date = Date.now
    public var dueDate: Date?

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

@Model
public final class DebtPayment {
    public var id: UUID = UUID()
    public var amount: Decimal = 0
    public var date: Date = Date.now
    public var note: String = ""

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
    public var totalPaid: Decimal {
        (payments ?? []).reduce(0) { $0 + $1.amount }
    }

    public static func openFirstSorted(_ records: [DebtRecord], now: Date = .now) -> [DebtRecord] {
        let open = records.filter { !$0.isSettled }
            .sorted { lhs, rhs in
                switch (lhs.isOverdue(now: now), rhs.isOverdue(now: now)) {
                case (true, false): return true
                case (false, true): return false
                default:
                    return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
                }
            }
        return open + records.filter(\.isSettled)
    }

    public var remaining: Decimal {
        max(0, principal - totalPaid)
    }

    public var isSettled: Bool {
        remaining <= 0
    }

    public func isOverdue(now: Date = .now) -> Bool {
        guard let dueDate, !isSettled else { return false }
        return dueDate < now
    }
}

public enum DebtSummary {
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
