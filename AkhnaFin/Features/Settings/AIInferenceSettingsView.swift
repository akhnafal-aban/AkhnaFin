import SwiftUI
import ServiceInterfaces

struct AIInferenceSettingsView: View {
    let keyStore: (any APIKeyStoring)?

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyActionError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(
                        hasStoredKey ? "Terpasang" : "Belum diisi",
                        systemImage: hasStoredKey ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(hasStoredKey ? .green : .orange)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                }
            }

            Section {
                SecureField("Tempel API key (wandb_v1…)", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Simpan Key") {
                    saveKey()
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("API Key")
            } footer: {
                Text("Dapatkan gratis di wandb.ai/authorize. Key disimpan di Keychain perangkat, tidak pernah ditampilkan kembali.")
            }

            if hasStoredKey {
                Section {
                    Button("Hapus Key", role: .destructive) {
                        deleteKey()
                    }
                }
            }
        }
        .navigationTitle("AI — W&B Inference")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshStatus() }
        .errorAlert("Gagal", message: $keyActionError)
    }

    private func refreshStatus() {
        hasStoredKey = keyStore?.read()?.isEmpty == false
    }

    private func saveKey() {
        do {
            try keyStore?.save(apiKeyInput.trimmingCharacters(in: .whitespaces))
            apiKeyInput = ""
            refreshStatus()
        } catch {
            keyActionError = (error as? LocalizedError)?.errorDescription ?? "Coba lagi."
        }
    }

    private func deleteKey() {
        do {
            try keyStore?.delete()
            refreshStatus()
        } catch {
            keyActionError = (error as? LocalizedError)?.errorDescription ?? "Coba lagi."
        }
    }
}