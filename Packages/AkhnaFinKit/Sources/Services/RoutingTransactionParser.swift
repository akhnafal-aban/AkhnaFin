import Foundation
import ServiceInterfaces

/// Router engine per-peran (PLAN-007): teks dan gambar masing-masing bisa
/// Apple lokal atau OpenRouter, dibaca dari `ModelPreferenceStoring` SAAT CALL
/// — ganti pilihan di Pengaturan langsung berlaku tanpa rebuild dependencies.
public struct RoutingTransactionParser: TransactionParsing {
    private let apple: AppleTransactionParser
    private let openRouter: OpenRouterParser
    private let preferenceStore: any ModelPreferenceStoring

    public init(
        apple: AppleTransactionParser,
        openRouter: OpenRouterParser,
        preferenceStore: any ModelPreferenceStoring
    ) {
        self.apple = apple
        self.openRouter = openRouter
        self.preferenceStore = preferenceStore
    }

    /// Graceful state UI mengikuti engine TEKS (jalur input utama);
    /// engine gambar dicek saat `parseReceipt`.
    public var availability: ParsingAvailability {
        resolve(preferenceStore.load().text).availability
    }

    public func parse(_ text: String) async throws -> TransactionDraft {
        try await resolve(preferenceStore.load().text).parse(text)
    }

    public func parseBatch(_ text: String) async throws -> [TransactionDraft] {
        try await resolve(preferenceStore.load().text).parseBatch(text)
    }

    public func parseReceipt(image: Data) async throws -> TransactionDraft {
        try await resolve(preferenceStore.load().image).parseReceipt(image: image)
    }

    private func resolve(_ engine: ParserEngine) -> any TransactionParsing {
        switch engine {
        case .appleLocal: apple
        case .openRouter: openRouter
        }
    }
}
