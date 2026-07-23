import Foundation
import ServiceInterfaces

/// Engine Apple lokal (PLAN-007): membungkus jalur on-device yang dipulihkan
/// dari PLAN-006 di balik protokol `TransactionParsing` terkini.
///
/// - Teks   → `FoundationModelsParser` (Apple Intelligence; English-only,
///            gagal di simulator — batasan FM iOS 26 yang terdokumentasi).
/// - Gambar → `VisionReceiptScanner` (OCR) → `ReceiptHeuristics` (deterministik)
///            — jalan OFFLINE, tanpa Apple Intelligence.
public struct AppleTransactionParser: TransactionParsing {
    private let foundationParser: FoundationModelsParser
    private let scanner = VisionReceiptScanner()
    private let personalization: (any PersonalizationProviding)?

    public init(
        categoryNames: [String],
        subcategoryNames: [String],
        personalization: (any PersonalizationProviding)? = nil
    ) {
        foundationParser = FoundationModelsParser(
            categoryNames: categoryNames,
            subcategoryNames: subcategoryNames
        )
        self.personalization = personalization
    }

    public var availability: ParsingAvailability {
        foundationParser.availability
    }

    public func parse(_ text: String) async throws -> TransactionDraft {
        let snippet = await personalization?.contextSnippet(for: text) ?? ""
        return try await foundationParser.parse(text, personalizationSnippet: snippet)
    }

    public func parseBatch(_ text: String) async throws -> [TransactionDraft] {
        var drafts: [TransactionDraft] = []
        for line in text.split(whereSeparator: \.isNewline) {
            drafts.append(try await parse(String(line)))
        }
        return drafts
    }

    /// Resi TIDAK butuh Apple Intelligence — OCR + heuristik deterministik.
    public func parseReceipt(image: Data) async throws -> TransactionDraft {
        let text = try await scanner.extractText(from: image)
        return try await foundationParser.parseReceipt(text: text)
    }
}
