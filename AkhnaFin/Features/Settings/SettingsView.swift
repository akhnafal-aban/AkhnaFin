import SwiftUI
import ServiceInterfaces
import Persistence

/// Pengaturan: API key AI, kelola kategori, rekam lokasi, status iCloud.
struct SettingsView: View {
    let repository: TransactionRepository
    /// Keychain store API key OpenRouter (nil = section AI disembunyikan, mis. Preview).
    var keyStore: (any APIKeyStoring)?

    /// Toggle auto-capture lokasi saat commit dalam-app (default ON — keputusan Fase 0).
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

    // MARK: - Section AI (OpenRouter)

    /// Key hanya mengalir SecureField → Keychain; tidak pernah ditampilkan kembali.
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
                Label("API Key OpenRouter", systemImage: "key")
            }

            SecureField("Tempel API key (sk-or-…)", text: $apiKeyInput)
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
            Text("AI — OpenRouter")
        } footer: {
            Text("Key disimpan di Keychain perangkat, tidak pernah ditampilkan kembali. Dipakai untuk Text Entry & Upload Resi (Nemotron + gpt-oss via OpenRouter).")
        }
        .alert(
            "Gagal menyimpan key",
            isPresented: Binding(
                get: { keyActionError != nil },
                set: { if !$0 { keyActionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keyActionError ?? "")
        }
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
    private var storageLabel: String { isCloud ? "iCloud" : "Lokal" }
    private var storageIcon: String { isCloud ? "checkmark.icloud" : "icloud.slash" }
    private var storageFooter: String {
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

