import Foundation

public enum ParsingAvailability: Sendable, Equatable {
    case available
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

public protocol TransactionParsing: Sendable {
    var availability: ParsingAvailability { get }

    func parse(_ text: String) async throws -> TransactionDraft

    func parseBatch(_ text: String) async throws -> [TransactionDraft]

    func parseReceipt(text: String) async throws -> TransactionDraft
}
