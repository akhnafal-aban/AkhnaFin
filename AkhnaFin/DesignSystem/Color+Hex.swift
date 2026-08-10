import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Warna adaptif dari hex "#RRGGBB" / "RRGGBB".
    ///
    /// Light mode: hex as-is.
    /// Dark mode: lighten L+0.12 (lebih terbaca di background gelap).
    /// High contrast: boost saturasi +0.15, adjust lightness.
    ///
    /// `nil`/invalid → accent color (fallback aman).
    init(hex: String?) {
        guard let hex, let rgb = Color.rgb(fromHex: hex) else {
            self = .accentColor
            return
        }
        #if canImport(UIKit)
        self = Color(UIColor { trait in
            let (h, s, l) = Color.rgbToHsl(rgb.r, rgb.g, rgb.b)
            let isDark = trait.userInterfaceStyle == .dark
            let isHC = trait.accessibilityContrast == .high

            let newL: Double
            let newS: Double
            if isHC {
                newL = isDark ? min(1, l + 0.18) : max(0, l - 0.08)
                newS = min(1, s + 0.15)
            } else if isDark {
                newL = min(1, l + 0.12)
                newS = s
            } else {
                newL = l
                newS = s
            }

            let (r, g, b) = Color.hslToRgb(h, newS, newL)
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
        #else
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
        #endif
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

    private static func rgbToHsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let maxVal = Swift.max(r, Swift.max(g, b))
        let minVal = Swift.min(r, Swift.min(g, b))
        let l = (maxVal + minVal) / 2

        guard maxVal != minVal else { return (0, 0, l) }

        let d = maxVal - minVal
        let s = l > 0.5 ? d / (2 - maxVal - minVal) : d / (maxVal + minVal)

        var h: Double
        if maxVal == r {
            h = (g - b) / d + (g < b ? 6 : 0)
        } else if maxVal == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h /= 6

        return (h, s, l)
    }

    private static func hslToRgb(_ h: Double, _ s: Double, _ l: Double) -> (r: Double, g: Double, b: Double) {
        guard s != 0 else { return (l, l, l) }

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q

        func hueToRgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }

        return (hueToRgb(p, q, h + 1.0 / 3.0), hueToRgb(p, q, h), hueToRgb(p, q, h - 1.0 / 3.0))
    }
}
