import Foundation

/// Ketersediaan parser — UI menampilkan graceful state bila model tidak tersedia
/// (tanpa heuristic fallback, sesuai keputusan arsitektur).
public enum ParsingAvailability: Sendable, Equatable {
    case available
    /// `reason` siap-tampil untuk user (mis. "Aktifkan Apple Intelligence di Settings").
    case unavailable(reason: String)
}

public enum TransactionParsingError: LocalizedError, Sendable, Equatable {
    case modelUnavailable(String)
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): reason
        case .parsingFailed(let reason): reason
        }
    }
}

/// Mengubah teks bahasa natural ("beli bakso 20k di kantin kantor") menjadi draft transaksi.
///
/// Implementasi utama: Foundation Models on-device (target `Services`, Fase 1).
public protocol TransactionParsing: Sendable {
    /// Cek sebelum menampilkan UI input NL; `parse` juga melempar bila unavailable.
    var availability: ParsingAvailability { get }

    func parse(_ text: String) async throws -> TransactionDraft

    /// Parse beberapa transaksi sekaligus (satu per baris, atau kalimat majemuk) — untuk batch entry.
    func parseBatch(_ text: String) async throws -> [TransactionDraft]
}
