import SwiftUI
import RezekiCore
import Persistence

/// Tambah/edit kategori. Jenis hanya bisa dipilih saat menambah kategori induk
/// (subkategori mewarisi induk; edit tak mengubah jenis agar transaksi konsisten).
struct CategoryEditView: View {
    enum Mode: Identifiable {
        case add(parent: TransactionCategory?, kind: TransactionType)
        case edit(TransactionCategory)

        var id: String {
            switch self {
            case .add(let parent, let kind): "add-\(parent?.id.uuidString ?? "root")-\(kind.rawValue)"
            case .edit(let category): "edit-\(category.id.uuidString)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    private let mode: Mode
    private let repository: TransactionRepository

    @State private var name: String
    @State private var iconName: String
    @State private var colorHex: String
    @State private var saveError: String?

    init(mode: Mode, repository: TransactionRepository) {
        self.mode = mode
        self.repository = repository
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _iconName = State(initialValue: Self.iconChoices[0])
            _colorHex = State(initialValue: Self.colorChoices[0])
        case .edit(let category):
            _name = State(initialValue: category.name)
            _iconName = State(initialValue: category.iconName)
            _colorHex = State(initialValue: category.colorHex.isEmpty ? Self.colorChoices[0] : category.colorHex)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: iconName)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color(hex: colorHex), in: RoundedRectangle(cornerRadius: 10))
                        TextField("Nama kategori", text: $name)
                    }
                }

                Section("Ikon") { iconGrid }
                Section("Warna") { colorRow }
            }
            .navigationTitle(navTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Gagal menyimpan", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "") }
        }
    }

    // MARK: - Pilihan ikon & warna

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
            ForEach(Self.iconChoices, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(iconName == symbol ? Color.white : Color.primary)
                    .background(
                        iconName == symbol ? Color(hex: colorHex) : Color(.secondarySystemFill),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .onTapGesture { iconName = symbol }
            }
        }
        .padding(.vertical, 4)
    }

    private var colorRow: some View {
        HStack(spacing: 12) {
            ForEach(Self.colorChoices, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 30, height: 30)
                    .overlay {
                        if colorHex == hex {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { colorHex = hex }
            }
        }
    }

    // MARK: - Simpan

    private var navTitle: String {
        switch mode {
        case .add(let parent, _): parent == nil ? "Kategori Baru" : "Subkategori Baru"
        case .edit: "Edit Kategori"
        }
    }

    private func save() {
        do {
            switch mode {
            case .add(let parent, let kind):
                try repository.addCategory(
                    name: name, iconName: iconName, colorHex: colorHex, kind: kind, parent: parent
                )
            case .edit(let category):
                try repository.updateCategory(
                    category, name: name, iconName: iconName, colorHex: colorHex
                )
            }
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "Gagal menyimpan."
        }
    }

    // Subset SF Symbols relevan finansial + palet warna kategori seed.
    private static let iconChoices = [
        "tag", "fork.knife", "cup.and.saucer", "cart", "bag", "gift",
        "car", "fuelpump", "bus", "airplane", "house", "bolt",
        "wifi", "phone", "cross.case", "pills", "figure.run", "gamecontroller",
        "film", "music.note", "book", "gym.bag", "banknote", "creditcard",
        "dollarsign.circle", "chart.line.uptrend.xyaxis", "sparkles", "heart", "pawprint", "wrench.and.screwdriver",
    ]
    private static let colorChoices = [
        "#F97316", "#8B5CF6", "#EF4444", "#3B82F6", "#10B981",
        "#22C55E", "#EAB308", "#EC4899", "#06B6D4", "#64748B",
    ]
}
