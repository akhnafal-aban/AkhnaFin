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
}
