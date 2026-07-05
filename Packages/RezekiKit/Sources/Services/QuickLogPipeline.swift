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
        case .timedOut: "Model terlalu lama merespons. Coba lagi sebentar lagi."
        }
    }
}

/// Orkestrasi parse dengan pagar waktu — dipakai App Intent (dan jalur lain
/// bila perlu). Berjalan di luar MainActor; hasil selalu `TransactionDraft`
/// yang masih harus dikonfirmasi user sebelum commit.
public struct QuickLogPipeline: Sendable {
    private let parser: any TransactionParsing
    private let timeout: Duration

    public init(parser: any TransactionParsing, timeout: Duration = .seconds(15)) {
        self.parser = parser
        self.timeout = timeout
    }

    public func parseDraft(from text: String) async throws -> TransactionDraft {
        do {
            return try await withThrowingTaskGroup(of: TransactionDraft.self) { group in
                let parser = self.parser
                let timeout = self.timeout
                group.addTask { try await parser.parse(text) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw QuickLogError.timedOut
                }
                defer { group.cancelAll() }
                // Pemenang pertama: hasil parse ATAU lemparan timeout.
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
