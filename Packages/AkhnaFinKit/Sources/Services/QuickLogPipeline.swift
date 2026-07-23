import Foundation
import ServiceInterfaces

/// Error granular jalur quick-log (intent/QuickAdd) — tiap kasus punya pesan
/// siap-tampil sendiri, supaya dialog Siri/alert tidak generik (BUG-2).
public enum QuickLogError: LocalizedError, Equatable, Sendable {
    case modelUnavailable(String)
    case parseFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): reason
        case .parseFailed(let reason): reason
        case .timedOut: "Prosesnya terlalu lama. Coba lagi sebentar lagi."
        }
    }
}

/// Orkestrasi parse dengan pagar waktu — dipakai App Intent & QuickAdd.
/// Berjalan di luar MainActor; hasil selalu `TransactionDraft` yang masih
/// harus dikonfirmasi user sebelum commit.
///
/// Timeout 45s = pagar total. `OpenRouterParser.complete()` sekarang satu call
/// + tangga fallback hingga 3 attempt (structured+reasoning → structured →
/// non-structured). Tangga HANYA memanjang pada 404 no-endpoints (cepat); pada
/// timeout, attempt melempar langsung tanpa retry, jadi worst case ≈ satu call
/// lambat + dua 404 cepat. Tiap call juga dibatasi per-request di
/// `OpenRouterClient` (30s), yang mencegah cold-start free-tier menembus pagar
/// ini dan memicu batal `-999` (bug device sesi 03).
public struct QuickLogPipeline: Sendable {
    private let parser: any TransactionParsing
    private let timeout: Duration

    public init(
        parser: any TransactionParsing,
        timeout: Duration = .seconds(45)
    ) {
        self.parser = parser
        self.timeout = timeout
    }

    /// Kalimat natural language → draft.
    public func parseDraft(from text: String) async throws -> TransactionDraft {
        let parser = self.parser
        return try await withTimeout { try await parser.parse(text) }
    }

    /// Kalimat → transaksi ATAU hutang (PLAN-008), pagar waktu sama.
    public func parseEntry(from text: String) async throws -> QuickEntry {
        let parser = self.parser
        return try await withTimeoutEntry { try await parser.parseEntry(text) }
    }

    /// Foto resi → draft (gambar langsung ke model multimodal, tanpa OCR terpisah).
    public func parseReceiptDraft(fromImage imageData: Data) async throws -> TransactionDraft {
        let parser = self.parser
        return try await withTimeout {
            try await parser.parseReceipt(image: imageData)
        }
    }

    // MARK: - Pagar waktu + mapping error (satu sumber untuk semua jalur)

    private func withTimeout(
        _ operation: @escaping @Sendable () async throws -> TransactionDraft
    ) async throws -> TransactionDraft {
        try await withTimeoutGeneric(operation)
    }

    private func withTimeoutEntry(
        _ operation: @escaping @Sendable () async throws -> QuickEntry
    ) async throws -> QuickEntry {
        try await withTimeoutGeneric(operation)
    }

    private func withTimeoutGeneric<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await withThrowingTaskGroup(of: Value.self) { group in
                let timeout = self.timeout
                group.addTask(operation: operation)
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw QuickLogError.timedOut
                }
                defer { group.cancelAll() }
                // Pemenang pertama: hasil operasi ATAU lemparan timeout.
                return try await group.next()!
            }
        } catch let error as QuickLogError {
            throw error
        } catch let error as TransactionParsingError {
            switch error {
            case .modelUnavailable(let reason): throw QuickLogError.modelUnavailable(reason)
            case .parsingFailed(let reason): throw QuickLogError.parseFailed(reason)
            }
        } catch is CancellationError {
            throw QuickLogError.timedOut
        } catch {
            throw QuickLogError.parseFailed("Terjadi kesalahan tak terduga saat memproses.")
        }
    }
}
