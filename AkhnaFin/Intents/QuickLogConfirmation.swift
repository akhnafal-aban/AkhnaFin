//
//  QuickLogConfirmation.swift
//  AkhnaFin
//
//  Helper bersama LogExpenseIntent & LogReceiptIntent: stash draft lalu sajikan
//  snippet interaktif sebagai HASIL intent (perform selesai seketika).
//
//  Dulu memakai `requestConfirmation` yang menahan perform di `await` → tombol
//  "Edit di App" tak bisa menutup snippet. Result snippet memperbaikinya:
//  commit/edit/batal ditangani tombol (SaveDraftIntent/EditExpenseInAppIntent/
//  CancelDraftIntent), masing-masing menutup snippet dengan benar.
//

import AppIntents
import SwiftUI
import AkhnaFinCore
import ServiceInterfaces

extension AppIntent {
    /// Stash draft lalu kembalikan snippet ringkasan + tombol aksi. Dialog
    /// terucap menyertai kartu.
    @MainActor
    func stashAndPresentDraft(
        _ draft: TransactionDraft,
        source: EntrySource,
        receiptImage: Data? = nil
    ) -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        PendingDraftStore.stash(draft, source: source, receiptImage: receiptImage)
        return .result(
            dialog: "Catat \(DraftSummary.text(of: draft))?",
            view: DraftSnippetView()
        )
    }

    /// Satu jalur hasil klasifikasi (sesi 03): transaksi → snippet aksi penuh;
    /// hutang → kartu deferral (arahkan ke Text Entry di app). View di-erase ke
    /// `AnyView` agar kedua cabang punya tipe balik `some` yang sama.
    @MainActor
    func presentQuickEntry(
        _ entry: QuickEntry,
        source: EntrySource
    ) -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        switch entry {
        case .transaction(let draft):
            PendingDraftStore.stash(draft, source: source)
            return .result(
                dialog: "Catat \(DraftSummary.text(of: draft))?",
                view: AnyView(DraftSnippetView())
            )
        case .debt(let draft):
            return .result(
                dialog: "Ini catatan hutang, bukan transaksi kas. Buka Text Entry di app untuk menyimpannya.",
                view: AnyView(DebtDeferralSnippetView(draft: draft))
            )
        }
    }
}
