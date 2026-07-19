//
//  QuickLogConfirmation.swift
//  AkhnaFin
//
//  Alur konfirmasi-lalu-simpan bersama LogExpenseIntent & LogReceiptIntent (A3).
//  Dulu diduplikat ~90% di kedua intent (review #2); satu sumber di sini.
//

import AppIntents
import OSLog
import AkhnaFinCore
import ServiceInterfaces
import Persistence

private let confirmLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Intent")

extension AppIntent {
    /// Stash draft → konfirmasi snippet interaktif → commit → bersihkan stash.
    ///
    /// Mengembalikan dialog siap-tampil (sukses ATAU gagal-simpan). MELEMPAR hanya saat
    /// user membatalkan konfirmasi — termasuk menekan "Edit di App", yang membatalkan
    /// `requestConfirmation` agar snippet menutup dan handoff ke app berjalan.
    ///
    /// Extension di `AppIntent` karena `requestConfirmation` adalah member intent,
    /// bukan fungsi bebas.
    @MainActor
    func confirmStashAndCommit(
        _ draft: TransactionDraft,
        source: EntrySource,
        receiptImage: Data? = nil
    ) async throws -> IntentDialog {
        PendingDraftStore.stash(draft, source: source, receiptImage: receiptImage)
        try await requestConfirmation(
            dialog: "Catat \(DraftSummary.text(of: draft))?",
            snippetIntent: ConfirmExpenseSnippetIntent()
        )
        // Commit DULU, bersihkan stash HANYA setelah sukses — bila simpan gagal, stash
        // tetap ada (dibersihkan saat app dibuka) alih-alih data ikut hilang (review #4).
        do {
            _ = try AppContainer.dependencies.repository.commit(
                draft, source: source, receiptImage: receiptImage
            )
        } catch {
            confirmLog.error("simpan gagal: \(String(describing: error), privacy: .public)")
            return "Draft benar, tapi gagal menyimpan. Coba lagi dari dalam app."
        }
        PendingDraftStore.clearStash()
        confirmLog.info("tersimpan (\(source.rawValue, privacy: .public))")
        return "Tercatat: \(DraftSummary.text(of: draft))."
    }
}
