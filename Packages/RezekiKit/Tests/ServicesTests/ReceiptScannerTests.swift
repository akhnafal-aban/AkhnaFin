import Testing
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
@testable import Services

/// Uji OCR TANPA fixture binary: resi sintetis dirender ke PNG via CoreGraphics/
/// CoreText di dalam test, lalu dibaca balik oleh VisionReceiptScanner.
@Suite("VisionReceiptScanner — OCR resi sintetis")
struct ReceiptScannerTests {
    @Test("Teks kunci resi terekstrak dari gambar", .timeLimit(.minutes(2)))
    func extractsSyntheticReceipt() async throws {
        let png = try Self.renderReceiptPNG(lines: [
            "TOKO MAJU JAYA",
            "Nasi Goreng   25.000",
            "Es Teh         5.000",
            "TOTAL         30.000",
        ])

        let text = try await VisionReceiptScanner().extractText(from: png)

        #expect(text.contains("MAJU"))
        #expect(text.contains("TOTAL"))
        #expect(text.contains("30"))
    }

    @Test("Gambar kosong menghasilkan teks kosong (bukan crash)")
    func blankImageYieldsEmpty() async throws {
        let png = try Self.renderReceiptPNG(lines: [])
        let text = try await VisionReceiptScanner().extractText(from: png)
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Render helper (putih, teks hitam besar — ramah OCR)

    private static func renderReceiptPNG(lines: [String], width: Int = 600) throws -> Data {
        let lineHeight = 48
        let height = max(200, lines.count * lineHeight + 80)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RenderError.contextFailed }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica" as CFString, 30, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key:
                    CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            // CoreGraphics origin kiri-bawah: baris ke-0 digambar paling atas.
            context.textPosition = CGPoint(x: 40, y: height - 60 - index * lineHeight)
            CTLineDraw(ctLine, context)
        }

        guard let image = context.makeImage() else { throw RenderError.imageFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { throw RenderError.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.encodeFailed }
        return data as Data
    }

    private enum RenderError: Error { case contextFailed, imageFailed, encodeFailed }
}
