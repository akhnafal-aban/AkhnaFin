import SwiftUI
import ServiceInterfaces
import Persistence

struct SettingsView: View {
    let repository: TransactionRepository
    var keyStore: (any APIKeyStoring)?

    @AppStorage("recordLocation") private var recordLocation = true
    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var keyActionError: String?

    var body: some View {
        NavigationStack {
            List {
                if keyStore != nil {
                    aiSection
                }

                Section("Data") {
                    NavigationLink {
                        CategoryManagementView(repository: repository)
                    } label: {
                        Label("Kelola Kategori", systemImage: "tag")
                    }
                }

                Section {
                    Toggle(isOn: $recordLocation) {
                        Label("Rekam Lokasi", systemImage: "location")
                    }
                } footer: {
                    Text("Menyimpan tempat transaksi secara otomatis saat kamu mencatat di dalam app. Izin lokasi diminta saat pertama kali.")
                }

                Section {
                    LabeledContent {
                        Text(storageLabel)
                    } label: {
                        Label("Penyimpanan", systemImage: storageIcon)
                    }
                } header: {
                    Text("Sinkronisasi")
                } footer: {
                    Text(storageFooter)
                }

                Section("Tentang") {
                    LabeledContent("Versi", value: appVersion)
                }
            }
            .navigationTitle("Pengaturan")
            .onAppear { hasStoredKey = keyStore?.read()?.isEmpty == false }
        }
    }

    // MARK: - Section AI (W&B Inference)

    private var aiSection: some View {
        Section {
            LabeledContent {
                Label(
                    hasStoredKey ? "Terpasang" : "Belum diisi",
                    systemImage: hasStoredKey ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(hasStoredKey ? .green : .orange)
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
            } label: {
                Label("API Key W&B", systemImage: "key")
            }

            SecureField("Tempel API key (wandb_v1…)", text: $apiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Simpan Key") {
                saveKey()
            }
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

            if hasStoredKey {
                Button("Hapus Key", role: .destructive) {
                    deleteKey()
                }
            }
        } header: {
            Text("AI — W&B Inference")
        } footer: {
            Text("Key disimpan di Keychain perangkat, tidak pernah ditampilkan kembali. Dipakai untuk Text Entry & Upload Resi (GLM 5.3).")
        }
        .errorAlert("Gagal menyimpan key", message: $keyActionError)
    }

    private func saveKey() {
        do {
            try keyStore?.save(apiKeyInput.trimmingCharacters(in: .whitespaces))
            apiKeyInput = ""
            hasStoredKey = true
        } catch {
            keyActionError = (error as? LocalizedError)?.errorDescription ?? "Coba lagi."
        }
    }

    private func deleteKey() {
        do {
            try keyStore?.delete()
            hasStoredKey = false
        } catch {
            keyActionError = (error as? LocalizedError)?.errorDescription ?? "Coba lagi."
        }
    }

    // MARK: - Status penyimpanan

    private var isCloud: Bool { AppContainer.activeStorageMode == .cloudKit }
    private var storageLabel: LocalizedStringResource { isCloud ? "iCloud" : "Lokal" }
    private var storageIcon: String { isCloud ? "checkmark.icloud" : "icloud.slash" }
    private var storageFooter: LocalizedStringResource {
        isCloud
            ? "Transaksimu tersinkron & ter-backup otomatis ke iCloud."
            : "iCloud tidak tersedia (mis. belum login). Data tersimpan lokal di perangkat ini saja."
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

