import Foundation
import AkhnaFinCore

public struct MockTransactionParser: TransactionParsing {
    public var template: TransactionDraft
    public var availability: ParsingAvailability
    public var delay: Duration
    public var error: TransactionParsingError?

    public init(
        template: TransactionDraft = TransactionDraft(
            amount: 20000,
            merchant: "Kantin Kantor",
            categoryName: "Main Food"
        ),
        availability: ParsingAvailability = .available,
        delay: Duration = .zero,
        error: TransactionParsingError? = nil
    ) {
        self.template = template
        self.availability = availability
        self.delay = delay
        self.error = error
    }

    public func parse(_ text: String) async throws -> TransactionDraft {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
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

    public func parseReceipt(text: String) async throws -> TransactionDraft {
        try await parse(text)
    }
}
