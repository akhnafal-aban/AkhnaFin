import SwiftUI
import SwiftData
import RezekiCore
import Persistence

/// Form tambah/edit transaksi manual — jalur commit pertama sebelum jalur AI dibangun.
struct AddEditTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TransactionCategory.name) private var allCategories: [TransactionCategory]

    private let repository: TransactionRepository
    private let existing: MoneyTransaction?

    @State private var type: TransactionType
    @State private var amount: Decimal
    @State private var date: Date
    @State private var merchant: String
    @State private var note: String
    @State private var category: TransactionCategory?
    @State private var saveFailed = false

    init(repository: TransactionRepository, transaction: MoneyTransaction? = nil) {
        self.repository = repository
        self.existing = transaction
        _type = State(initialValue: transaction?.type ?? .expense)
        _amount = State(initialValue: transaction?.amount ?? 0)
        _date = State(initialValue: transaction?.date ?? .now)
        _merchant = State(initialValue: transaction?.merchant ?? "")
        _note = State(initialValue: transaction?.note ?? "")
        _category = State(initialValue: transaction?.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Jenis", selection: $type) {
                    Text("Pengeluaran").tag(TransactionType.expense)
                    Text("Pemasukan").tag(TransactionType.income)
                    Text("Transfer").tag(TransactionType.transfer)
                }
                .pickerStyle(.segmented)

                Section("Nominal") {
                    AmountField(amount: $amount)
                }

                Section("Detail") {
                    CategoryPicker(categories: allCategories.selectable(for: type), selection: $category)
                    DatePicker("Tanggal", selection: $date)
                    TextField("Merchant / tempat beli", text: $merchant)
                    TextField("Catatan", text: $note)
                }
            }
            .keyboardDismissable()
            .navigationTitle(existing == nil ? "Transaksi Baru" : "Edit Transaksi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .disabled(amount <= 0)
                }
            }
            .onChange(of: type) {
                if category?.kind != type { category = nil }
            }
            .alert("Gagal menyimpan transaksi", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func save() {
        do {
            if let existing {
                existing.type = type
                existing.amount = amount
                existing.date = date
                existing.merchant = merchant
                existing.note = note
                existing.category = category
                try repository.save()
            } else {
                let transaction = MoneyTransaction(
                    amount: amount,
                    type: type,
                    date: date,
                    note: note,
                    merchant: merchant,
                    source: .manual,
                    category: category
                )
                try repository.create(transaction)
            }
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    try! CategorySeeder.seedIfNeeded(context: container.mainContext)
    let repository = TransactionRepository(context: container.mainContext)
    return AddEditTransactionView(repository: repository)
        .modelContainer(container)
}
