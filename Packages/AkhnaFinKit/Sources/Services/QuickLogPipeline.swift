import Foundation
import ServiceInterfaces

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

public struct QuickLogPipeline: Sendable {
    private let parser: any TransactionParsing
    private let scanner: (any ReceiptScanning)?
    private let timeout: Duration

    public init(
        parser: any TransactionParsing,
        scanner: (any ReceiptScanning)? = nil,
        timeout: Duration = .seconds(45)
    ) {
        self.parser = parser
        self.scanner = scanner
        self.timeout = timeout
    }

    public func parseDraft(from text: String) async throws -> TransactionDraft {
        let parser = self.parser
        return try await withTimeout { try await parser.parse(text) }
    }

    public func parseReceiptDraft(fromImage imageData: Data) async throws -> TransactionDraft {
        guard let scanner else {
            throw QuickLogError.parseFailed("Scanner resi tidak terpasang.")
        }
        let parser = self.parser
        return try await withTimeout {
            let text = try await scanner.extractText(from: imageData)
            return try await parser.parseReceipt(text: text)
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
