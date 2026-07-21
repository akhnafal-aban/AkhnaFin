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
/// Timeout 25s: pipeline OpenRouter = dua call berantai (perception → generator)
/// dengan latensi free-tier yang variabel.
public struct QuickLogPipeline: Sendable {
    private let parser: any TransactionParsing
    private let timeout: Duration

    public init(
        parser: any TransactionParsing,
        timeout: Duration = .seconds(25)
    ) {
        self.parser = parser
        self.timeout = timeout
    }

    /// Kalimat natural language → draft.
    public func parseDraft(from text: String) async throws -> TransactionDraft {
        let parser = self.parser
        return try await withTimeout { try await parser.parse(text) }
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
        do {
            return try await withThrowingTaskGroup(of: TransactionDraft.self) { group in
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
