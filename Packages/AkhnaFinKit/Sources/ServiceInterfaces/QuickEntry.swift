import Foundation
import AkhnaFinCore

/// Draft catatan hutang/piutang hasil parsing — seperti `TransactionDraft`,
/// SELALU dikonfirmasi/diedit user sebelum disimpan (pipeline sakral).
public struct DebtDraft: Sendable, Equatable, Codable {
    public var counterparty: String
    public var direction: DebtDirection
    public var amount: Decimal
    public var note: String
    public var rawInput: String

    public init(
        counterparty: String = "",
        direction: DebtDirection = .iOwe,
        amount: Decimal = 0,
        note: String = "",
        rawInput: String = ""
    ) {
        self.counterparty = counterparty
        self.direction = direction
        self.amount = amount
        self.note = note
        self.rawInput = rawInput
    }
}

/// Hasil parse satu kalimat Text Entry: transaksi kas ATAU catatan hutang
/// ("utang ke Budi 50k", "SPayLater 300k jatuh tempo bulan depan").
public enum QuickEntry: Sendable, Equatable {
    case transaction(TransactionDraft)
    case debt(DebtDraft)
}

extension TransactionParsing {
    /// Default: parser yang belum paham hutang (mis. engine Apple lama) selalu
    /// menghasilkan transaksi — perilaku lama tak berubah.
    public func parseEntry(_ text: String) async throws -> QuickEntry {
        .transaction(try await parse(text))
    }
}
