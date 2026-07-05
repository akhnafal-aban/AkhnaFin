import SwiftUI
import SwiftData
import RezekiCore
import ServiceInterfaces
import Persistence

/// Konfirmasi draft hasil AI sebelum disimpan — pola yang dipakai ulang semua
/// jalur capture (QuickAdd, nanti Siri/Voice/struk/batch). Hasil AI TIDAK PERNAH
/// di-commit tanpa melewati layar ini.
struct ConfirmDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TransactionCategory.name) private var allCategories: [TransactionCategory]

    private let repository: TransactionRepository
    private let rawInput: String
    private let suggestedCategoryName: String
    private let suggestedSubcategoryName: String
    private let source: EntrySource
    private let onCommitted: () -> Void

    @State private var type: TransactionType
    @State private var amount: Decimal
    @State private var date: Date
    @State private var merchant: String
    @State private var note: String
    @State private var category: TransactionCategory?
    @State private var didResolveSuggestion = false
    @State private var saveFailed = false

    init(
        draft: TransactionDraft,
        repository: TransactionRepository,
        source: EntrySource = .quickAdd,
        onCommitted: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.rawInput = draft.rawInput
        self.suggestedCategoryName = draft.categoryName
        self.suggestedSubcategoryName = draft.subcategoryName
        self.source = source
        self.onCommitted = onCommitted
        _type = State(initialValue: draft.type)
        _amount = State(initialValue: draft.amount)
        _date = State(initialValue: draft.date)
        _merchant = State(initialValue: draft.merchant)
        _note = State(initialValue: draft.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !rawInput.isEmpty {
                    Section("Dari kalimatmu") {
                        Text("“\(rawInput)”")
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }

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
            .navigationTitle("Konfirmasi Transaksi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .disabled(amount <= 0)
                }
            }
            .onAppear(perform: resolveSuggestedCategoryOnce)
            .onChange(of: type) {
                if category?.kind != type { category = nil }
            }
            .alert("Gagal menyimpan transaksi", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    /// Preselect kategori dari saran parser — sekali saja, agar pilihan user tidak tertimpa.
    private func resolveSuggestedCategoryOnce() {
        guard !didResolveSuggestion else { return }
        didResolveSuggestion = true
        if !suggestedSubcategoryName.isEmpty,
           let sub = try? repository.resolveCategory(named: suggestedSubcategoryName, kind: type) {
            category = sub
            return
        }
        if !suggestedCategoryName.isEmpty {
            category = try? repository.resolveCategory(named: suggestedCategoryName, kind: type)
        }
    }

    private func save() {
        // Draft final dari state hasil editan user — tetap lewat pipeline commit().
        var categoryName = ""
        var subcategoryName = ""
        if let category {
            if let parent = category.parent {
                categoryName = parent.name
                subcategoryName = category.name
            } else {
                categoryName = category.name
            }
        }
        let draft = TransactionDraft(
            amount: amount,
            type: type,
            date: date,
            note: note,
            merchant: merchant,
            categoryName: categoryName,
            subcategoryName: subcategoryName,
            rawInput: rawInput
        )
        do {
            try repository.commit(draft, source: source)
            onCommitted()
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    try! CategorySeeder.seedIfNeeded(context: container.mainContext)
    return ConfirmDraftView(
        draft: TransactionDraft(
            amount: 20000,
            note: "bakso",
            merchant: "Kantin Kantor",
            categoryName: "Main Food",
            rawInput: "beli bakso 20k di kantin kantor"
        ),
        repository: TransactionRepository(context: container.mainContext)
    )
    .modelContainer(container)
}
