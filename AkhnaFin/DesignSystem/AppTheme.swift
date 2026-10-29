import SwiftUI

enum AppTheme {
    static let background = Color("AppBackground")
    static let surface = Color("AppSurface")
    static let ink = Color("AppInk")
    static let lime = Color("AppLime")
    static let expenseRed = Color("AppExpenseRed")
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