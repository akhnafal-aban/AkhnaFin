//
//  ConfirmExpenseSnippet.swift
//  AkhnaFin
//

import AppIntents
import SwiftUI
import OSLog
import AkhnaFinCore
import ServiceInterfaces
import Persistence

private let snippetLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Intent")

// MARK: - Tombol snippet (aksi)

struct SaveDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Simpan Transaksi"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let payload = PendingDraftStore.currentStashPayload() else {
            return .result(dialog: "Draft tidak ditemukan.")
        }
        do {
            _ = try AppContainer.dependencies.repository.commit(
                payload.draft, source: payload.source, receiptImage: payload.receiptImage
            )
        } catch {
            snippetLog.error("SaveDraft gagal: \(String(describing: error), privacy: .public)")
            return .result(dialog: "Draft benar, tapi gagal menyimpan. Coba dari dalam app.")
        }
        PendingDraftStore.clearStash()
        snippetLog.info("SaveDraft tersimpan (\(payload.source.rawValue, privacy: .public))")
        return .result(dialog: "Tercatat: \(DraftSummary.text(of: payload.draft)).")
    }
}

struct EditExpenseInAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Edit Draft di App"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingDraftStore.promoteStashToEditRequest()
        return .result()
    }
}

struct CancelDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Batalkan"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PendingDraftStore.clearStash()
        return .result(dialog: "Dibatalkan.")
    }
}

// MARK: - Kartu snippet

struct DraftSnippetView: View {
    private var draft: TransactionDraft? { PendingDraftStore.currentStash() }

    var body: some View {
        if let draft {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.tint)
                    Text(CurrencyFormatter.string(from: draft.amount, currencyCode: draft.currencyCode))
                        .font(.title2.bold().monospacedDigit())
                    Spacer()
                    Text(draft.type.displayName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let (icon, text) = descriptor(of: draft) {
                        row(icon, text)
                    }
                    row("calendar", draft.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                }
                .font(.subheadline)

                HStack(spacing: 8) {
                    Button(intent: SaveDraftIntent()) {
                        Label("Simpan", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(intent: EditExpenseInAppIntent()) {
                        Label("Edit", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button(intent: CancelDraftIntent()) {
                    Text("Batal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
            .padding()
        } else {
            Text("Draft tidak ditemukan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    private func descriptor(of draft: TransactionDraft) -> (icon: String, text: String)? {
        if !draft.categoryName.isEmpty {
            let text = draft.subcategoryName.isEmpty
                ? draft.categoryName
                : "\(draft.categoryName) › \(draft.subcategoryName)"
            return ("tag", text)
        }
        if !draft.merchant.isEmpty { return ("storefront", draft.merchant) }
        if !draft.note.isEmpty { return ("text.alignleft", draft.note) }
        return nil
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(text).lineLimit(1)
        }
    }
}
