//
//  ConfirmExpenseSnippet.swift
//  My RezekiKu
//
//  Snippet interaktif iOS 26 (A3 / BUG-1b): saat konfirmasi intent, user melihat
//  kartu ringkasan draft + tombol "Edit di App" — bukan sekadar dialog biner.
//

import AppIntents
import SwiftUI
import RezekiCore
import ServiceInterfaces

/// Snippet ringkasan draft yang tampil di UI konfirmasi Siri/Shortcuts.
struct ConfirmExpenseSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Ringkasan Draft Transaksi"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(view: DraftSnippetView(draft: PendingDraftStore.currentStash()))
    }
}

/// Dipicu tombol "Edit di App" di snippet: pindahkan draft ke slot handoff
/// lalu buka app — RootView mendeteksi dan menyajikan TransactionFormView (mode confirmDraft).
struct EditExpenseInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Edit Draft di App"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let draft = PendingDraftStore.currentStash() {
            PendingDraftStore.requestEditInApp(draft, receiptImage: PendingDraftStore.currentStashImage())
        }
        return .result()
    }
}

private struct DraftSnippetView: View {
    let draft: TransactionDraft?

    var body: some View {
        if let draft {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.tint)
                    Text(CurrencyFormatter.string(from: draft.amount, currencyCode: draft.currencyCode))
                        .font(.title2.bold().monospacedDigit())
                    Spacer()
                    Text(typeLabel(draft.type))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !draft.categoryName.isEmpty {
                        row("tag", draft.subcategoryName.isEmpty
                            ? draft.categoryName
                            : "\(draft.categoryName) › \(draft.subcategoryName)")
                    }
                    if !draft.merchant.isEmpty { row("storefront", draft.merchant) }
                    if !draft.note.isEmpty { row("text.alignleft", draft.note) }
                    row("calendar", draft.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                }
                .font(.subheadline)

                if !draft.rawInput.isEmpty {
                    Text("“\(draft.rawInput)”")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }

                Button(intent: EditExpenseInAppIntent()) {
                    Label("Edit di App", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        } else {
            Text("Draft tidak ditemukan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(text).lineLimit(1)
        }
    }

    private func typeLabel(_ type: TransactionType) -> String {
        switch type {
        case .expense: "Pengeluaran"
        case .income: "Pemasukan"
        case .transfer: "Transfer"
        }
    }
}
