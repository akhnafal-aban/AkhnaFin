//
//  QuickLogConfirmation.swift
//  AkhnaFin
//
//  Helper bersama intent log: stash draft → snippet hasil (perform selesai
//  seketika). Tombol aksi = intent tersendiri di ConfirmExpenseSnippet.
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
