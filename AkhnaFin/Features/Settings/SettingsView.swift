import SwiftUI
import ServiceInterfaces
import Persistence

struct SettingsView: View {
    let repository: TransactionRepository
    var keyStore: (any APIKeyStoring)?

    @AppStorage("recordLocation") private var recordLocation = true
    @State private var hasStoredKey = false

    var body: some View {
        NavigationStack {
            List {
                if keyStore != nil {
                    Section("AI") {
                        NavigationLink {
                            AIInferenceSettingsView(keyStore: keyStore)
                        } label: {
                            LabeledContent {
                                Text(hasStoredKey ? "Terpasang" : "Belum diisi")
                                    .font(.subheadline)
                                    .foregroundStyle(hasStoredKey ? .green : .secondary)
                            } label: {
                                Label("W&B Inference", systemImage: "wand.and.stars")
                            }
                        }
                    }
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

