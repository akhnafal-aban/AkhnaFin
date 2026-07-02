import Foundation

/// Mengubah teks bahasa natural ("beli bakso 20k di kantin kantor") menjadi draft transaksi.
///
/// Implementasi utama: Foundation Models on-device (target `Services`, Fase 1).
public protocol TransactionParsing: Sendable {
    func parse(_ text: String) async throws -> TransactionDraft

    /// Parse beberapa transaksi sekaligus (satu per baris, atau kalimat majemuk) — untuk batch entry.
    func parseBatch(_ text: String) async throws -> [TransactionDraft]
}
