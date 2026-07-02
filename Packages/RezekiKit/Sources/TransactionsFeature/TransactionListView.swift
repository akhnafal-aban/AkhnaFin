import SwiftUI
import SwiftData
import RezekiCore
import Persistence
import DesignSystem

/// Daftar transaksi: section per tanggal, pencarian, swipe edit/hapus.
///
/// Read reaktif lewat `@Query` (MVVM hybrid); mutasi lewat `TransactionRepository`.
public struct TransactionListView: View {
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @State private var searchText = ""
    @State private var isAdding = false
    @State private var editingTransaction: MoneyTransaction?

    private let repository: TransactionRepository

    public init(repository: TransactionRepository) {
        self.repository = repository
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

    public var body: some View {
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
                                        try? repository.delete(transaction)
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
            .searchable(text: $searchText, prompt: "Cari merchant, catatan, kategori")
            .toolbar {
                Button {
                    isAdding = true
                } label: {
                    Label("Tambah", systemImage: "plus")
                }
            }
            .sheet(isPresented: $isAdding) {
                AddEditTransactionView(repository: repository)
            }
            .sheet(item: $editingTransaction) { transaction in
                AddEditTransactionView(repository: repository, transaction: transaction)
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
