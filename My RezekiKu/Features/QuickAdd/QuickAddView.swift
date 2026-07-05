import SwiftUI
import SwiftData
import RezekiCore
import ServiceInterfaces
import Persistence

/// Catat cepat: ketik satu kalimat ("beli bakso 20k di kantin kantor") →
/// parser on-device mengisi draft → user konfirmasi/edit → tersimpan.
struct QuickAddView: View {
    private let parser: any TransactionParsing
    private let repository: TransactionRepository

    @State private var input = ""
    @State private var isParsing = false
    @State private var pending: PendingDraft?
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    init(parser: any TransactionParsing, repository: TransactionRepository) {
        self.parser = parser
        self.repository = repository
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
                    "buy meatballs 20k at the office canteen",
                    text: $input,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .focused($inputFocused)
                .submitLabel(.go)
                .onSubmit(parse)
            } header: {
                Text("Tulis transaksimu dalam satu kalimat (Bahasa Inggris)")
            } footer: {
                Text("Contoh: \"pay electricity 350k yesterday\", \"salary came in 8m\", \"movie tickets 50k\"")
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
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .keyboardDismissable()
        .sheet(item: $pending) { pending in
            ConfirmDraftView(draft: pending.draft, repository: repository) {
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
        Task {
            do {
                let draft = try await parser.parse(text)
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
