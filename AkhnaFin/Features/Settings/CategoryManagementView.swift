import SwiftUI
import SwiftData
import AkhnaFinCore
import Persistence

/// Kelola kategori: daftar per jenis (induk + subkategori indent), tambah/edit/hapus.
/// Read reaktif via `@Query`; mutasi lewat `TransactionRepository`.
struct CategoryManagementView: View {
    let repository: TransactionRepository

    @Query(sort: \TransactionCategory.name) private var categories: [TransactionCategory]
    @State private var editorMode: CategoryEditView.Mode?
    @State private var deleteError: String?

    var body: some View {
        List {
            section(for: .expense, title: "Pengeluaran")
            section(for: .income, title: "Pemasukan")
        }
        .navigationTitle("Kategori")
        .toolbar {
            Menu {
                Button { editorMode = .add(parent: nil, kind: .expense) } label: {
                    Label("Kategori Pengeluaran", systemImage: "arrow.down.circle")
                }
                Button { editorMode = .add(parent: nil, kind: .income) } label: {
                    Label("Kategori Pemasukan", systemImage: "arrow.up.circle")
                }
            } label: {
                Label("Tambah", systemImage: "plus")
            }
        }
        .sheet(item: $editorMode) { mode in
            CategoryEditView(mode: mode, repository: repository)
        }
        .alert("Tidak bisa menghapus", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(deleteError ?? "") }
    }

    private func section(for kind: TransactionType, title: String) -> some View {
        let parents = categories.filter { $0.parent == nil && $0.kind == kind }
        return Section(title) {
            ForEach(parents) { parent in
                categoryRow(parent, indent: false)
                    .swipeActions(edge: .trailing) {
                        deleteButton(parent)
                        Button {
                            editorMode = .add(parent: parent, kind: kind)
                        } label: { Label("Sub", systemImage: "plus") }
                            .tint(.blue)
                    }

                ForEach((parent.subcategories ?? []).sorted { $0.name < $1.name }) { sub in
                    categoryRow(sub, indent: true)
                        .swipeActions(edge: .trailing) { deleteButton(sub) }
                }
            }
        }
    }

    private func categoryRow(_ category: TransactionCategory, indent: Bool) -> some View {
        Button {
            editorMode = .edit(category)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.iconName)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(hex: category.colorHex), in: RoundedRectangle(cornerRadius: 7))
                Text(category.name)
                    .foregroundStyle(.primary)
                Spacer()
                if category.isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, indent ? 24 : 0)
        }
    }

    private func deleteButton(_ category: TransactionCategory) -> some View {
        Button(role: .destructive) {
            do {
                try repository.deleteCategory(category)
            } catch {
                deleteError = (error as? LocalizedError)?.errorDescription ?? "Gagal menghapus."
            }
        } label: { Label("Hapus", systemImage: "trash") }
    }
}
