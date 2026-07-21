//
//  ConfirmExpenseSnippet.swift
//  AkhnaFin
//
//  Snippet interaktif iOS 26 (result snippet, BUKAN requestConfirmation modal):
//  kartu ringkasan draft + tiga tombol aksi (Simpan / Edit di App / Batal), tiap
//  tombol AppIntent tersendiri yang dismiss/handoff dengan benar.
//
//  Kenapa bukan requestConfirmation: modal itu menahan `perform()` di `await`
//  sehingga tombol "Edit di App" yang membuka app TIDAK pernah menutup snippet
//  (bug device terverifikasi). Result snippet menyelesaikan perform seketika —
//  membuka app lewat tombol menutup snippet (pola kanonik WWDC25 sesi 275).
//

import AppIntents
import SwiftUI
import OSLog
import AkhnaFinCore
import ServiceInterfaces
import Persistence

private let snippetLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Intent")

// MARK: - Tombol snippet (aksi)

/// "Simpan": commit draft dari stash di background (tanpa buka app), lalu tutup
/// snippet dengan dialog hasil.
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
        // Konfirmasi tanpa edit = penguat sinyal kategori (best-effort).
        try? AppContainer.dependencies.signalRepository.record(
            merchant: payload.draft.merchant,
            bank: "",
            noteKeywords: "\(payload.draft.rawInput) \(payload.draft.note)",
            categoryName: payload.draft.categoryName,
            edited: false
        )
        snippetLog.info("SaveDraft tersimpan (\(payload.source.rawValue, privacy: .public))")
        return .result(dialog: "Tercatat: \(DraftSummary.text(of: payload.draft)).")
    }
}

/// "Edit di App": pindahkan draft ke slot handoff lalu buka app. Karena snippet
/// ini result snippet (bukan modal), membuka app menutup snippet — RootView
/// mendeteksi handoff dan menyajikan TransactionFormView (mode confirmDraft).
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

/// "Batal": buang draft, tutup snippet.
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

/// Kartu ringkas + tiga tombol. Sengaja minimalis (nominal + jenis + satu
/// deskriptor + tanggal); detail penuh muncul di form setelah "Edit di App".
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

    /// Satu baris deskriptor terpenting: kategori (dengan sub) → merchant → catatan.
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
