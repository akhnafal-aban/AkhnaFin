import Foundation
import OSLog
import Vision
import ServiceInterfaces

private let ocrSignposter = OSSignposter(subsystem: "com.aban.AkhnaFin", category: "Parser")
private let ocrLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Parser")

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
