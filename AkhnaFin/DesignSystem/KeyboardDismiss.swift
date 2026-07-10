import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Keyboard selalu bisa ditutup (BUG-3): scroll menutup segera, tap di mana pun
    /// menutup SAAT keyboard tampil (gated — tap saat keyboard tertutup tetap
    /// memfokuskan field secara normal), plus tombol "Selesai" di atas keyboard.
    func keyboardDismissable() -> some View {
        modifier(KeyboardDismissable())
    }
}

private struct KeyboardDismissable: ViewModifier {
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                TapGesture().onEnded(endEditing),
                including: keyboardVisible ? .all : .subviews
            )
        #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        #endif
    }
}

private func endEditing() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
    #endif
}
