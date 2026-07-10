import SwiftUI
import Persistence

/// Pengaturan: kelola kategori, rekam lokasi, status penyimpanan iCloud.
struct SettingsView: View {
    let repository: TransactionRepository

    /// Toggle auto-capture lokasi saat commit dalam-app (default ON — keputusan Fase 0).
    @AppStorage("recordLocation") private var recordLocation = true

    var body: some View {
        NavigationStack {
            List {
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

/// Stub sementara — diisi penuh di slice S4.
struct CategoryManagementView: View {
    let repository: TransactionRepository

    var body: some View {
        ContentUnavailableView("Kelola Kategori", systemImage: "tag", description: Text("Segera hadir."))
            .navigationTitle("Kategori")
    }
}
