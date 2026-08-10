import SwiftUI
import SwiftData
import AkhnaFinCore
import ServiceInterfaces
import Persistence

/// SATU form transaksi untuk tiga jalur (A5 — konsolidasi duplikasi):
/// tambah manual, edit, dan konfirmasi draft hasil AI. Hasil AI TIDAK PERNAH
/// tersimpan tanpa melewati layar ini (mode `.confirmDraft`).
struct TransactionFormView: View {
    enum Mode {
        case add
        case edit(MoneyTransaction)
        case confirmDraft(TransactionDraft, source: EntrySource, receiptImage: Data?)
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TransactionCategory.name) private var allCategories: [TransactionCategory]

    private let mode: Mode
    private let repository: TransactionRepository
    /// Untuk auto-capture lokasi senyap saat menyimpan transaksi BARU (nil = nonaktif,
    /// mis. Preview/edit). Gating akhir tetap lewat `LocationPreference`.
    private let locationService: (any LocationCapturing)?
    /// Belajar personalisasi kategori dari commit jalur AI (nil = tidak merekam).
    private let signalRepository: SignalRepository?
    private let onCommitted: () -> Void

    @State private var type: TransactionType
    @State private var amount: Decimal
    @State private var date: Date
    @State private var merchant: String
    @State private var note: String
    @State private var category: TransactionCategory?
    @State private var didResolveSuggestion = false
    @State private var saveFailed = false
    @State private var isSaving = false

    @State private var isReimbursable: Bool
    @State private var reimbursedBy: String = ""

    init(
        mode: Mode,
        repository: TransactionRepository,
        locationService: (any LocationCapturing)? = nil,
        signalRepository: SignalRepository? = nil,
        onCommitted: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.repository = repository
        self.locationService = locationService
        self.signalRepository = signalRepository
        self.onCommitted = onCommitted

        let initial: (TransactionType, Decimal, Date, String, String, TransactionCategory?)
        var reimbursableInitial = false
        var reimbursedByInitial = ""
        switch mode {
        case .add:
            initial = (.expense, 0, .now, "", "", nil)
        case .edit(let transaction):
            initial = (
                transaction.type, transaction.amount, transaction.date,
                transaction.merchant, transaction.note, transaction.category
            )
            reimbursableInitial = transaction.isReimbursable
            reimbursedByInitial = transaction.reimbursedBy
        case .confirmDraft(let draft, _, _):
            initial = (draft.type, draft.amount, draft.date, draft.merchant, draft.note, nil)
            reimbursableInitial = draft.isReimbursable
            reimbursedByInitial = draft.reimbursedBy
        }
        _type = State(initialValue: initial.0)
        _amount = State(initialValue: initial.1)
        _date = State(initialValue: initial.2)
        _merchant = State(initialValue: initial.3)
        _note = State(initialValue: initial.4)
        _category = State(initialValue: initial.5)
        _isReimbursable = State(initialValue: reimbursableInitial)
        _reimbursedBy = State(initialValue: reimbursedByInitial)
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
                    ForEach(TransactionType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
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

                if isEditing || type == .expense || type == .income {
                    Section {
                        Toggle(isOn: $isReimbursable) {
                            Text(type == .income ? "Ini pinjaman" : "Ini talangan")
                        }
                        if isReimbursable {
                            TextField("Nama teman", text: $reimbursedBy)
                        }
                    } header: {
                        Text(type == .income ? "Pinjaman" : "Talangan")
                    } footer: {
                        if isReimbursable && !isEditing {
                            Text( reimbursableFooter)
                        }
                    }
                }
            }
            .keyboardDismissable()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Simpan") { save() }
                            .disabled(amount <= 0)
                    }
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

    // MARK: - Mode helpers

    private var title: String {
        switch mode {
        case .add: "Transaksi Baru"
        case .edit: "Edit Transaksi"
        case .confirmDraft: "Konfirmasi Transaksi"
        }
    }

    private var rawInput: String {
        if case .confirmDraft(let draft, _, _) = mode { draft.rawInput } else { ""
        }
    }

    /// Talangan bisa disetel di: add (expense), confirmDraft (expense), atau edit (reimbursable existing).
    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    /// Footer dinamis berdasarkan jenis transaksi.
    private var reimbursableFooter: String {
        if type == .income {
            "Pemasukan ini adalah uang pinjaman. Saldo bank bertambah, tapi otomatis membuat catatan utang. Saat dibayar balik, catat sebagai pembayaran cicilan utang (bukan pengeluaran baru)."
        } else {
            "Transaksi dicatat sebagai pengeluaran (saldo bank berkurang), tapi otomatis membuat catatan piutang. Saat dibayar balik, catat sebagai pembayaran cicilan hutang (bukan pemasukan baru)."
        }
    }

    /// Preselect kategori dari saran parser — sekali saja (mode confirmDraft).
    private func resolveSuggestedCategoryOnce() {
        guard case .confirmDraft(let draft, _, _) = mode, !didResolveSuggestion else { return }
        didResolveSuggestion = true
        if !draft.subcategoryName.isEmpty,
           let sub = try? repository.resolveCategory(named: draft.subcategoryName, kind: type) {
            category = sub
            return
        }
        if !draft.categoryName.isEmpty {
            category = try? repository.resolveCategory(named: draft.categoryName, kind: type)
        }
    }

    // MARK: - Simpan

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let place = await capturePlaceIfNeeded()
            do {
                try persist(place: place)
                onCommitted()
                dismiss()
            } catch {
                saveFailed = true
                isSaving = false
            }
        }
    }

    /// Auto-capture lokasi hanya untuk transaksi BARU (add/confirmDraft), bila
    /// service terpasang & toggle "Rekam Lokasi" aktif. Edit tak menyentuh lokasi.
    private func capturePlaceIfNeeded() async -> CapturedPlace? {
        guard let locationService, LocationPreference.isEnabled else { return nil }
        switch mode {
        case .add, .confirmDraft: return await locationService.captureCurrent()
        case .edit: return nil
        }
    }

    private func persist(place: CapturedPlace?) throws {
        switch mode {
        case .add:
            if isReimbursable {
                try repository.createReimbursable(
                    amount: amount, type: type, date: date,
                    note: note, merchant: merchant,
                    reimbursedBy: reimbursedBy, category: category,
                    place: place
                )
            } else {
                let transaction = MoneyTransaction(
                    amount: amount, type: type, date: date, note: note,
                    merchant: merchant, source: .manual, category: category
                )
                if let place {
                    transaction.latitude = place.latitude
                    transaction.longitude = place.longitude
                    transaction.placeName = place.placeName
                }
                try repository.create(transaction)
            }

        case .edit(let transaction):
            transaction.type = type
            transaction.amount = amount
            transaction.date = date
            transaction.merchant = merchant
            transaction.note = note
            transaction.category = category
            transaction.isReimbursable = isReimbursable
            transaction.reimbursedBy = reimbursedBy
            try repository.save()

        case .confirmDraft(let draft, let source, let receiptImage):
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
            let finalDraft = TransactionDraft(
                amount: amount, currencyCode: draft.currencyCode, type: type,
                date: date, note: note, merchant: merchant,
                categoryName: categoryName, subcategoryName: subcategoryName,
                rawInput: draft.rawInput,
                isReimbursable: isReimbursable, reimbursedBy: reimbursedBy
            )
            try repository.commit(finalDraft, source: source, place: place, receiptImage: receiptImage)

            let edited = categoryName != draft.categoryName
                || subcategoryName != draft.subcategoryName
            try? signalRepository?.record(
                merchant: merchant,
                bank: "",
                noteKeywords: "\(draft.rawInput) \(note)",
                categoryName: categoryName,
                edited: edited
            )
        }
    }
}

#Preview("Konfirmasi draft") {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    try! CategorySeeder.seedIfNeeded(context: container.mainContext)
    return TransactionFormView(
        mode: .confirmDraft(
            TransactionDraft(
                amount: 20000, note: "bakso", merchant: "Kantin Kantor",
                categoryName: "Main Food", rawInput: "buy meatballs 20k"
            ),
            source: .quickAdd,
            receiptImage: nil
        ),
        repository: TransactionRepository(context: container.mainContext)
    )
    .modelContainer(container)
}
