import Foundation

public struct MockReceiptScanner: ReceiptScanning {
    public var text: String

    public init(text: String = "TOKO MAJU JAYA\nNasi Goreng 25.000\nTOTAL 25.000") {
        self.text = text
    }

    public func extractText(from imageData: Data) async throws -> String {
        text
    }
}
