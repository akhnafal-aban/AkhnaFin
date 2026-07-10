import SwiftUI
import SwiftData
import AkhnaFinCore
import ServiceInterfaces
import Persistence

/// Daftar transaksi: section per tanggal, pencarian, swipe edit/hapus.
///
/// Read reaktif lewat `@Query` (MVVM hybrid); mutasi lewat `TransactionRepository`.
struct TransactionListView: View {
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @State private var searchText = ""
    @State private var isAdding = false
    @State private var editingTransaction: MoneyTransaction?
    @State private var deleteFailed = false

    private let repository: TransactionRepository
    private let locationService: (any LocationCapturing)?

    init(repository: TransactionRepository, locationService: (any LocationCapturing)? = nil) {
        self.repository = repository
        self.locationService = locationService
    }

    private var filteredTransactions: [MoneyTransaction] {
        guard !searchText.isEmpty else { return Array(transactions) }
        let query = searchText.lowercased()
        return transactions.filter { transaction in
            transaction.merchant.lowercased().contains(query)
                || transaction.note.lowercased().contains(query)
                || (transaction.category?.name.lowercased().contains(query) ?? false)
                || transaction.placeName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(TransactionGrouping.groupByDay(filteredTransactions), id: \.day) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            TransactionRow(transaction)
                                .contentShape(Rectangle())
                                .onTapGesture { editingTransaction = transaction }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        do {
                                            try repository.delete(transaction)
                                        } catch {
                                            deleteFailed = true
                                        }
                                    } label: {
                                        Label("Hapus", systemImage: "trash")
                                    }
                                    Button {
                                        editingTransaction = transaction
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                    }
                }
            }
            .navigationTitle("Transaksi")
            .toolbarTitleDisplayMode(.inlineLarge)
            .searchable(text: $searchText, prompt: "Cari merchant, catatan, kategori")
            .toolbar {
                Button {
                    isAdding = true
                } label: {
                    Label("Tambah", systemImage: "plus")
                }
            }
            .sheet(isPresented: $isAdding) {
                TransactionFormView(mode: .add, repository: repository, locationService: locationService)
            }
            .sheet(item: $editingTransaction) { transaction in
                TransactionFormView(mode: .edit(transaction), repository: repository)
            }
            .alert("Gagal menghapus transaksi", isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
            }
            .overlay {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "Belum ada transaksi",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + untuk mencatat transaksi pertamamu.")
                    )
                } else if filteredTransactions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    try! CategorySeeder.seedIfNeeded(context: container.mainContext)
    let repository = TransactionRepository(context: container.mainContext)
    return TransactionListView(repository: repository)
        .modelContainer(container)
}
