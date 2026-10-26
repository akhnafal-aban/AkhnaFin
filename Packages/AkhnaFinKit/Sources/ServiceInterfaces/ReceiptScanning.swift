import Foundation

public protocol ReceiptScanning: Sendable {
    func extractText(from imageData: Data) async throws -> String
}
