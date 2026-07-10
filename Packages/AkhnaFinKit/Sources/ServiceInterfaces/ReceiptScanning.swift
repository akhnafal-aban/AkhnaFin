import Foundation

/// Ekstraksi teks berstruktur dari foto struk (implementasi: Vision `RecognizeDocumentsRequest`, Fase 4).
///
/// API minimal untuk saat ini; akan diperluas pada Fase 4 (mis. hasil per baris/tabel).
public protocol ReceiptScanning: Sendable {
    /// Ekstrak teks dari data gambar struk untuk diteruskan ke `TransactionParsing`.
    func extractText(from imageData: Data) async throws -> String
}
