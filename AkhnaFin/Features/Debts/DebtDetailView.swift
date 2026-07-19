import SwiftUI
import AkhnaFinCore
import Persistence

/// Detail satu hutang: progres, riwayat cicilan, bayar/lunasi/edit.
struct DebtDetailView: View {
    let record: DebtRecord
    let repository: DebtRepository

    @State private var isEditing = false
    @State private var isPaying = false
    @State private var paymentAmount: Decimal = 0
    @State private var confirmSettle = false
    @State private var actionError: String?

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.counterparty).font(.title3.weight(.semibold))
                        Text(record.direction.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if record.isSettled {
                        Label("Lunas", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                    } else if record.isOverdue() {
                        // HIG: jangan andalkan warna saja — ikon + teks.
                        Label("Terlambat", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline.weight(.semibold))
                    }
                }

                ProgressView(value: progressValue) {
                    HStack {
                        Text("Dibayar \(CurrencyFormatter.string(from: record.totalPaid))")
                        Spacer()
                        Text("Sisa \(CurrencyFormatter.string(from: record.remaining))")
                            .fontWeight(.semibold)
                    }
                    .font(.footnote)
                }

                LabeledContent("Pokok", value: CurrencyFormatter.string(from: record.principal))
                if let dueDate = record.dueDate {
                    LabeledContent("Jatuh tempo") {
                        Text(dueDate, format: .dateTime.day().month(.wide).year())
                            .foregroundStyle(record.isOverdue() ? .red : .primary)
                    }
                }
                if !record.note.isEmpty {
                    LabeledContent("Catatan", value: record.note)
                }
            }

            if !record.isSettled {
                Section {
                    Button {
                        paymentAmount = record.remaining
                        isPaying = true
                    } label: {
                        Label("Bayar Cicilan", systemImage: "banknote")
                    }
                    Button {
                        confirmSettle = true
                    } label: {
                        Label("Lunasi Sekarang", systemImage: "checkmark.seal")
                    }
                }
            }

            if let payments = record.payments, !payments.isEmpty {
                Section("Riwayat Pembayaran") {
                    ForEach(payments.sorted { $0.date > $1.date }, id: \.id) { payment in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CurrencyFormatter.string(from: payment.amount))
                                    .font(.body.monospacedDigit())
                                if !payment.note.isEmpty {
                                    Text(payment.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(payment.date, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Detail Hutang")
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            DebtFormView(mode: .edit(record), repository: repository)
        }
        .sheet(isPresented: $isPaying) {
            paymentSheet
        }
        .confirmationDialog(
            "Lunasi \(CurrencyFormatter.string(from: record.remaining))?",
            isPresented: $confirmSettle,
            titleVisibility: .visible
        ) {
            Button("Lunasi") { settle() }
            Button("Batal", role: .cancel) {}
        }
        .alert(
            "Gagal",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var progressValue: Double {
        guard record.principal > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: record.totalPaid).doubleValue
            / NSDecimalNumber(decimal: record.principal).doubleValue)
    }

    private var paymentSheet: some View {
        NavigationStack {
            Form {
                Section("Nominal Cicilan") {
                    AmountField(amount: $paymentAmount)
                }
            }
            .navigationTitle("Bayar Cicilan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { isPaying = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") { addPayment() }
                        .disabled(paymentAmount <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addPayment() {
        do {
            try repository.addPayment(paymentAmount, to: record)
            isPaying = false
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Coba lagi."
        }
    }

    private func settle() {
        do {
            try repository.settle(record)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? "Coba lagi."
        }
    }
}
