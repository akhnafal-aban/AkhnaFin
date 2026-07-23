import SwiftUI
import SwiftData
import PhotosUI
import AkhnaFinCore
import ServiceInterfaces
import Services
import Persistence

/// Daftar transaksi: section per tanggal, pencarian, swipe edit/hapus.
///
/// Read reaktif lewat `@Query` (MVVM hybrid); mutasi lewat `TransactionRepository`.
/// Toolbar "+" = HIG pull-down button: satu tombol dengan menu tiga jalur capture
/// (Text Entry / Upload Resi / Manual) — menggantikan tab "Catat Cepat".
struct TransactionListView: View {
    @Query(sort: \MoneyTransaction.date, order: .reverse) private var transactions: [MoneyTransaction]
    @State private var searchText = ""
    @State private var isAdding = false
    @State private var editingTransaction: MoneyTransaction?
    @State private var deleteFailed = false

    // Jalur capture dari menu "+"
    @State private var isTextEntryPresented = false
    @State private var isReceiptPickerPresented = false
    @State private var receiptItem: PhotosPickerItem?
    @State private var isParsingReceipt = false
    @State private var receiptDraft: ReceiptDraft?
    @State private var receiptError: String?

    private let repository: TransactionRepository
    private let parser: (any TransactionParsing)?
    private let locationService: (any LocationCapturing)?
    private let signalRepository: SignalRepository?
    private let debtRepository: DebtRepository?

    init(
        repository: TransactionRepository,
        parser: (any TransactionParsing)? = nil,
        locationService: (any LocationCapturing)? = nil,
        signalRepository: SignalRepository? = nil,
        debtRepository: DebtRepository? = nil
    ) {
        self.repository = repository
        self.parser = parser
        self.locationService = locationService
        self.signalRepository = signalRepository
        self.debtRepository = debtRepository
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
                // HIG pull-down button: aksi kreasi terkait dikonsolidasi di satu
                // tombol; item prioritas tinggi (jalur tersering) di urutan atas.
                Menu {
                    if parser != nil {
                        Button {
                            isTextEntryPresented = true
                        } label: {
                            Label("Text Entry", systemImage: "square.and.pencil")
                        }
                        Button {
                            isReceiptPickerPresented = true
                        } label: {
                            Label("Upload Resi", systemImage: "photo.on.rectangle")
                        }
                    }
                    Button {
                        isAdding = true
                    } label: {
                        Label("Manual", systemImage: "plus.circle")
                    }
                } label: {
                    if isParsingReceipt {
                        ProgressView()
                    } else {
                        Label("Tambah", systemImage: "plus")
                    }
                }
                .disabled(isParsingReceipt)
            }
            .sheet(isPresented: $isAdding) {
                TransactionFormView(mode: .add, repository: repository, locationService: locationService)
            }
            .sheet(isPresented: $isTextEntryPresented) {
                if let parser {
                    QuickAddView(
                        parser: parser,
                        repository: repository,
                        locationService: locationService,
                        signalRepository: signalRepository,
                        debtRepository: debtRepository
                    )
                }
            }
            .photosPicker(
                isPresented: $isReceiptPickerPresented,
                selection: $receiptItem,
                matching: .images
            )
            .onChange(of: receiptItem) {
                if let receiptItem {
                    parseReceipt(from: receiptItem)
                }
            }
            .sheet(item: $receiptDraft) { pending in
                TransactionFormView(
                    mode: .confirmDraft(pending.draft, source: .receipt, receiptImage: pending.imageData),
                    repository: repository,
                    locationService: locationService,
                    signalRepository: signalRepository
                )
            }
            .alert(
                "Gagal membaca resi",
                isPresented: Binding(
                    get: { receiptError != nil },
                    set: { if !$0 { receiptError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(receiptError ?? "")
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

    // MARK: - Jalur Upload Resi

    /// Foto galeri → Data → pipeline OCR+heuristik yang sama dgn Shortcut resi →
    /// draft konfirmasi. Gagal → alert pesan siap-tampil dari `QuickLogError`.
    private func parseReceipt(from item: PhotosPickerItem) {
        guard let parser, !isParsingReceipt else { return }
        isParsingReceipt = true
        receiptItem = nil  // reset agar pilihan sama bisa dipilih ulang
        let pipeline = QuickLogPipeline(parser: parser)
        Task {
            defer { isParsingReceipt = false }
            do {
                guard let imageData = try await item.loadTransferable(type: Data.self) else {
                    receiptError = "Gambar tidak bisa dibaca. Coba pilih foto lain."
                    return
                }
                let draft = try await pipeline.parseReceiptDraft(fromImage: imageData)
                receiptDraft = ReceiptDraft(draft: draft, imageData: imageData)
            } catch {
                receiptError = (error as? LocalizedError)?.errorDescription
                    ?? "Gagal membaca resi. Coba lagi."
            }
        }
    }
}

/// Pembungkus Identifiable untuk sheet(item:) — draft resi + gambar aslinya.
private struct ReceiptDraft: Identifiable {
    let id = UUID()
    let draft: TransactionDraft
    let imageData: Data
}

#Preview {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    try! CategorySeeder.seedIfNeeded(context: container.mainContext)
    let repository = TransactionRepository(context: container.mainContext)
    return TransactionListView(
        repository: repository,
        parser: MockTransactionParser()
    )
    .modelContainer(container)
}
