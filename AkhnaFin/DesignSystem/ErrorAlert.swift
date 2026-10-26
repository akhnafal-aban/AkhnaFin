import SwiftUI

extension View {
    /// Alert satu pesan dari `Binding<String?>`: terisi = tampil, tombol OK
    /// mengosongkan. Satu pola untuk semua form/daftar (8 call site).
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

    /// Varian tanpa teks pesan untuk flag `Bool`.
    func errorAlert(_ title: String, isPresented: Binding<Bool>) -> some View {
        alert(title, isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        }
    }
}