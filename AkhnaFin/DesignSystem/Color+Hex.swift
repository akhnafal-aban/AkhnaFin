import SwiftUI

extension Color {
    /// Warna dari hex "#RRGGBB" / "RRGGBB". `nil` → warna aksen (fallback aman).
    init(hex: String?) {
        guard let hex, let rgb = Color.rgb(fromHex: hex) else {
            self = .accentColor
            return
        }
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private static func rgb(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
