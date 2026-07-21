import Foundation

/// Ketersediaan parser — UI menampilkan graceful state bila tidak tersedia
/// (mis. API key belum diisi), tanpa heuristic fallback.
public enum ParsingAvailability: Sendable, Equatable {
    case available
    /// `reason` siap-tampil untuk user (mis. "Masukkan API key OpenRouter di Pengaturan").
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

/// Mengubah teks bahasa natural ("beli bakso 20k di kantin kantor") atau foto
/// resi menjadi draft transaksi.
///
/// Implementasi utama: `OpenRouterParser` 2-stage (PLAN-006) — Nemotron omni
/// (perception teks/gambar) → gpt-oss-120b (transaction generator).
public protocol TransactionParsing: Sendable {
    /// Cek sebelum menampilkan UI input NL; `parse` juga melempar bila unavailable.
    var availability: ParsingAvailability { get }

    func parse(_ text: String) async throws -> TransactionDraft

    /// Parse beberapa transaksi sekaligus (satu per baris, atau kalimat majemuk) — untuk batch entry.
    func parseBatch(_ text: String) async throws -> [TransactionDraft]

    /// Foto/screenshot resi belanja → draft: total akhir, merchant, ringkasan
    /// item, saran kategori. Selalu expense. Gambar langsung ke model multimodal
    /// (tanpa OCR terpisah).
    func parseReceipt(image: Data) async throws -> TransactionDraft
}

/// Konteks personalisasi perilaku kategori user (knowledge-graph mini SwiftData,
/// PLAN-006 Slice C) — disuntikkan ke prompt transaction generator.
public protocol PersonalizationProviding: Sendable {
    /// Baris asosiasi relevan utk `input` ("indomaret → Main Food (kuat)");
    /// string kosong bila belum ada sinyal.
    func contextSnippet(for input: String) async -> String
}
