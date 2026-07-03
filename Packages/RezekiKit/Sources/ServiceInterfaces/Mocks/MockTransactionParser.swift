import Foundation
import RezekiCore

/// Parser palsu untuk unit test & SwiftUI Preview — tanpa dependensi AI/device.
public struct MockTransactionParser: TransactionParsing {
    /// Draft dasar yang dikembalikan; `rawInput` selalu diisi teks asli yang di-parse.
    public var template: TransactionDraft
    public var availability: ParsingAvailability

    public init(
        template: TransactionDraft = TransactionDraft(
            amount: 20000,
            merchant: "Kantin Kantor",
            categoryName: "Main Food"
        ),
        availability: ParsingAvailability = .available
    ) {
        self.template = template
        self.availability = availability
    }

    public func parse(_ text: String) async throws -> TransactionDraft {
        var draft = template
        draft.rawInput = text
        return draft
    }

    public func parseBatch(_ text: String) async throws -> [TransactionDraft] {
        var drafts: [TransactionDraft] = []
        for line in text.split(whereSeparator: \.isNewline) {
            drafts.append(try await parse(String(line)))
        }
        return drafts
    }
}
