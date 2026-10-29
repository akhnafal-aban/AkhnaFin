import SwiftUI

enum AppTheme {
    static let background = Color(hex: "#1A1714")
    static let surface = Color(hex: "#26221E")
    static let ink = Color(hex: "#F2EEE8")
    static let lime = Color(hex: "#A3E635")
    static let expenseRed = Color(hex: "#EF7B64")
}

extension View {
    func warmDarkBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppTheme.background)
    }

    func warmRow() -> some View {
        listRowBackground(AppTheme.surface)
    }
}