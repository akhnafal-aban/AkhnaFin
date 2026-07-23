import SwiftUI
import AkhnaFinCore
import ServiceInterfaces
import Persistence

/// Form tambah/edit catatan hutang — pola state-dari-mode `TransactionFormView`.
struct DebtFormView: View {
    enum Mode {
        case add
        case edit(DebtRecord)
        /// Draft hasil parsing Text Entry (PLAN-008) — prefilled, tetap
        /// dikonfirmasi user sebelum tersimpan (pipeline sakral).
        case confirmDraft(DebtDraft)
    }

    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    private let repository: DebtRepository

    @State private var counterparty: String
    @State private var direction: DebtDirection
    @State private var principal: Decimal
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var note: String
    @State private var saveError: String?

    init(mode: Mode, repository: DebtRepository) {
        self.mode = mode
        self.repository = repository
        switch mode {
        case .add:
            _counterparty = State(initialValue: "")
            _direction = State(initialValue: .iOwe)
            _principal = State(initialValue: 0)
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: .now)
            _note = State(initialValue: "")
        case .edit(let record):
            _counterparty = State(initialValue: record.counterparty)
            _direction = State(initialValue: record.direction)
            _principal = State(initialValue: record.principal)
            _hasDueDate = State(initialValue: record.dueDate != nil)
            _dueDate = State(initialValue: record.dueDate ?? .now)
            _note = State(initialValue: record.note)
        case .confirmDraft(let draft):
            _counterparty = State(initialValue: draft.counterparty)
            _direction = State(initialValue: draft.direction)
            _principal = State(initialValue: draft.amount)
            _hasDueDate = State(initialValue: false)
            _dueDate = State(initialValue: .now)
            _note = State(initialValue: draft.note)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Arah", selection: $direction) {
                    ForEach(DebtDirection.allCases, id: \.self) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                Section("Pihak") {
                    TextField("Nama orang / platform (mis. SPayLater)", text: $counterparty)
                }
                Section("Pokok Hutang") {
                    AmountField(amount: $principal)
                }
                Section("Jatuh Tempo") {
                    Toggle("Ada jatuh tempo", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Tanggal", selection: $dueDate, displayedComponents: .date)
                    }
                }
                Section("Catatan") {
                    TextField("Opsional", text: $note)
                }
            }
            .keyboardDismissable()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { save() }
                        .disabled(principal <= 0 || trimmedCounterparty.isEmpty)
                }
            }
            .alert(
                "Gagal menyimpan",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var title: String {
        switch mode {
        case .edit: "Edit Hutang"
        case .add: "Hutang Baru"
        case .confirmDraft: "Konfirmasi Hutang"
        }
    }

    private var trimmedCounterparty: String {
        counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        do {
            switch mode {
            case .add, .confirmDraft:
                try repository.create(
                    counterparty: trimmedCounterparty,
                    direction: direction,
                    principal: principal,
                    note: note,
                    dueDate: hasDueDate ? dueDate : nil
                )
            case .edit(let record):
                record.counterparty = trimmedCounterparty
                record.direction = direction
                record.principal = principal
                record.note = note
                record.dueDate = hasDueDate ? dueDate : nil
                try repository.save()
            }
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "Coba lagi."
        }
    }
}
