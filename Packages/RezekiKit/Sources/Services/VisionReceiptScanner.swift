import Foundation
import OSLog
import Vision
import ServiceInterfaces

private let ocrSignposter = OSSignposter(subsystem: "com.aban.My-RezekiKu", category: "Parser")
private let ocrLog = Logger(subsystem: "com.aban.My-RezekiKu", category: "Parser")

/// OCR resi berbasis Vision `RecognizeDocumentsRequest` (iOS 26/macOS 26) —
/// struktur dokumen (baris/tabel) lebih akurat untuk resi daripada OCR polos.
/// Teks mentah diteruskan ke parser resi; validasi isi terjadi di pipeline.
public struct VisionReceiptScanner: ReceiptScanning {
    public init() {}

    public func extractText(from imageData: Data) async throws -> String {
        let interval = ocrSignposter.beginInterval("ocr")
        defer { ocrSignposter.endInterval("ocr", interval) }

        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: imageData)
        let text = observations
            .map(\.document.text.transcript)
            .joined(separator: "\n")
        ocrLog.info("ocr selesai: \(observations.count) dokumen, \(text.count) chars")
        return text
    }
}
