//
//  QuickLogConfirmation.swift
//  AkhnaFin
//

import AppIntents
import SwiftUI
import AkhnaFinCore
import ServiceInterfaces

extension AppIntent {
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
