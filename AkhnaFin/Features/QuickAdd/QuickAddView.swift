import SwiftUI
import SwiftData
import AkhnaFinCore
import ServiceInterfaces
import Services
import Persistence

/// Catat cepat: ketik satu kalimat ("beli bakso 20k di kantin kantor") →
/// parser on-device mengisi draft → user konfirmasi/edit → tersimpan.
struct QuickAddView: View {
    private let parser: any TransactionParsing
    private let repository: TransactionRepository
    private let locationService: (any LocationCapturing)?

    @State private var input = ""
    @State private var isParsing = false
    @State private var pending: PendingDraft?
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    init(
        parser: any TransactionParsing,
        repository: TransactionRepository,
        locationService: (any LocationCapturing)? = nil
    ) {
        self.parser = parser
        self.repository = repository
        self.locationService = locationService
    }

    var body: some View {
        NavigationStack {
            Group {
                switch parser.availability {
                case .available:
                    inputForm
                case .unavailable(let reason):
                    ContentUnavailableView {
                        Label("Parser tidak tersedia", systemImage: "wand.and.stars.inverse")
                    } description: {
                        Text(reason)
                    }
                }
            }
            .navigationTitle("Catat Cepat")
        }
    }

    private var inputForm: some View {
        Form {
            Section {
                TextField(
                    "buy [food] [xxk] at the [places]",
                    text: $input,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .focused($inputFocused)
                .submitLabel(.go)
                .onSubmit(parse)
            }
            Section {
                Button(action: parse) {
                    if isParsing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Memproses…")
                        }
                    } else {
                        Label("Buat Draft", systemImage: "wand.and.stars")
                    }
                }
                .disabled(trimmedInput.isEmpty || isParsing)
            }
        }
        .alert(
            "Gagal memproses",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .keyboardDismissable()
        .sheet(item: $pending) { pending in
            TransactionFormView(
                mode: .confirmDraft(pending.draft, source: .quickAdd, receiptImage: nil),
                repository: repository,
                locationService: locationService
            ) {
                input = ""
                inputFocused = true
            }
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parse() {
        guard !trimmedInput.isEmpty, !isParsing else { return }
        errorMessage = nil
        isParsing = true
        let text = trimmedInput
        let pipeline = QuickLogPipeline(parser: parser)
        Task {
            do {
                // Pipeline yang sama dgn App Intent: pagar waktu + error granular.
                let draft = try await pipeline.parseDraft(from: text)
                pending = PendingDraft(draft: draft)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Gagal memproses kalimat. Coba lagi."
            }
            isParsing = false
        }
    }
}

/// Pembungkus Identifiable agar draft bisa dipresentasikan via sheet(item:).
private struct PendingDraft: Identifiable {
    let id = UUID()
    let draft: TransactionDraft
}

#Preview {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    try! CategorySeeder.seedIfNeeded(context: container.mainContext)
    return QuickAddView(
        parser: MockTransactionParser(),
        repository: TransactionRepository(context: container.mainContext)
    )
    .modelContainer(container)
}
