import SwiftUI

extension View {
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    func errorAlert(_ title: String, isPresented: Binding<Bool>) -> some View {
        alert(title, isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        }
    }
}
