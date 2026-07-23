import SwiftUI
import ServiceInterfaces
import Services

/// Konfigurasi engine AI per peran (PLAN-007): teks & gambar masing-masing
/// Apple lokal atau model OpenRouter pilihan user dari katalog.
struct ModelSettingsView: View {
    enum Role { case text, image }

    let store: any ModelPreferenceStoring
    let catalog: OpenRouterModelCatalog

    @State private var preference: ModelPreference = .standard

    var body: some View {
        List {
            roleSection(
                role: .text,
                title: "Parsing Teks",
                appleFootnote: "Apple lokal: Foundation Models on-device — hanya Bahasa Inggris, butuh Apple Intelligence aktif."
            )
            roleSection(
                role: .image,
                title: "Parsing Gambar (Resi)",
                appleFootnote: "Apple lokal: OCR + heuristik di perangkat — jalan offline, tanpa Apple Intelligence, tanpa AI generatif."
            )
        }
        .navigationTitle("Model AI")
        .onAppear { preference = store.load() }
    }

    private func engine(for role: Role) -> ParserEngine {
        role == .text ? preference.text : preference.image
    }

    private func setEngine(_ engine: ParserEngine, for role: Role) {
        switch role {
        case .text: preference.text = engine
        case .image: preference.image = engine
        }
        store.save(preference)
    }

    @ViewBuilder
    private func roleSection(role: Role, title: String, appleFootnote: String) -> some View {
        let current = engine(for: role)
        Section {
            // Dua pilihan engine; OpenRouter membawa layar pilih model.
            Button {
                setEngine(.appleLocal, for: role)
            } label: {
                HStack {
                    Label("Apple (Lokal)", systemImage: "apple.logo")
                        .foregroundStyle(.primary)
                    Spacer()
                    if current == .appleLocal {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }

            NavigationLink {
                ModelPickerView(
                    catalog: catalog,
                    imageRoleOnly: role == .image,
                    selectedSlug: currentOpenRouterSlug(for: role)
                ) { model in
                    setEngine(.openRouter(
                        slug: model.slug,
                        supportsStructured: model.supportsStructured,
                        displayName: model.name
                    ), for: role)
                }
            } label: {
                HStack {
                    Label("OpenRouter", systemImage: "cloud")
                    Spacer()
                    if case .openRouter(_, _, let name) = current {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(appleFootnote)
        }
    }

    private func currentOpenRouterSlug(for role: Role) -> String? {
        if case .openRouter(let slug, _, _) = engine(for: role) { slug } else { nil }
    }
}

/// Daftar model OpenRouter dari katalog publik — searchable, filter gratis,
/// filter image-capable otomatis untuk peran gambar.
struct ModelPickerView: View {
    let catalog: OpenRouterModelCatalog
    let imageRoleOnly: Bool
    let selectedSlug: String?
    let onSelect: (CatalogModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var models: [CatalogModel] = []
    @State private var searchText = ""
    @State private var freeOnly = true
    @State private var loadError: String?
    @State private var isLoading = false

    private var filtered: [CatalogModel] {
        models.filter { model in
            (!imageRoleOnly || model.acceptsImage)
                && (!freeOnly || model.isFree)
                && (searchText.isEmpty
                    || model.name.localizedCaseInsensitiveContains(searchText)
                    || model.slug.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        List {
            Toggle("Hanya Gratis", isOn: $freeOnly)

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }

            ForEach(filtered) { model in
                Button {
                    onSelect(model)
                    dismiss()
                } label: {
                    row(model)
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle(imageRoleOnly ? "Model Gambar" : "Model Teks")
        .searchable(text: $searchText, prompt: "Cari nama / slug model")
        .task { await load() }
        .refreshable { await load(force: true) }
        .overlay {
            if let loadError {
                ContentUnavailableView(
                    "Gagal memuat katalog",
                    systemImage: "wifi.exclamationmark",
                    description: Text(loadError)
                )
            } else if !isLoading && filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func row(_ model: CatalogModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.isFree
                        ? "Gratis"
                        : String(format: "$%.2f/M in · $%.2f/M out",
                                 model.promptPricePerMillion, model.completionPricePerMillion))
                    if model.supportsStructured {
                        Text("JSON")
                            .padding(.horizontal, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                    if model.acceptsImage {
                        Image(systemName: "photo")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if model.slug == selectedSlug {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
    }

    private func load(force: Bool = false) async {
        isLoading = true
        loadError = nil
        do {
            models = try await catalog.models(forceRefresh: force)
        } catch {
            loadError = "Periksa koneksi internet, lalu tarik untuk memuat ulang."
        }
        isLoading = false
    }
}
