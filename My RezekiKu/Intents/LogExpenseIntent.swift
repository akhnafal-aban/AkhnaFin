//
//  LogExpenseIntent.swift
//  My RezekiKu
//
//  Siri/Shortcuts/Spotlight/Action Button → catat transaksi dari satu kalimat.
//  Wajib di app bundle. Hasil AI DIKONFIRMASI dulu sebelum commit (aturan pipeline).
//

import AppIntents
import OSLog
import RezekiCore
import ServiceInterfaces
import Services
import Persistence

private let intentLog = Logger(subsystem: "com.aban.My-RezekiKu", category: "Intent")

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Catat Pengeluaran"
    static let description = IntentDescription(
        "Catat transaksi dari satu kalimat Bahasa Inggris, mis. \"buy meatballs 20k at the canteen\"."
    )
    // Jalan di background (tanpa buka app); konfirmasi muncul sebagai prompt Siri/Shortcuts.
    static let openAppWhenRun = false

    @Parameter(
        title: "Transaksi",
        requestValueDialog: "Apa yang mau dicatat? (Bahasa Inggris)"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Container & wiring dibangun sekali per proses (BUG-2a) — bukan per invocation.
        let dependencies = AppContainer.dependencies
        intentLog.info("LogExpense mulai (\(text.count, privacy: .public) chars)")

        // Parse dengan pagar waktu — error granular, tidak pernah stuck (BUG-2b).
        let draft: TransactionDraft
        do {
            draft = try await QuickLogPipeline(parser: dependencies.parser).parseDraft(from: text)
            intentLog.info("LogExpense parse sukses")
        } catch let error as QuickLogError {
            intentLog.error("LogExpense parse gagal: \(String(describing: error), privacy: .public)")
            return .result(dialog: "\(error.errorDescription ?? "Gagal memproses.")")
        }

        // Konfirmasi-dulu dengan snippet interaktif (A3): kartu ringkasan +
        // tombol "Edit di App". Draft di-stash agar snippet bisa merender
        // dan jalur edit bisa handoff ke app.
        PendingDraftStore.stash(draft)
        do {
            try await requestConfirmation(
                dialog: "Catat \(DraftSummary.text(of: draft))?",
                snippetIntent: ConfirmExpenseSnippetIntent()
            )
        } catch {
            // Batal / pindah ke jalur edit: bersihkan slot konfirmasi.
            // (Slot handoff edit terpisah dan tetap utuh bila user memilih Edit.)
            PendingDraftStore.clearStash()
            intentLog.info("LogExpense konfirmasi dibatalkan")
            throw error
        }
        PendingDraftStore.clearStash()

        do {
            _ = try dependencies.repository.commit(draft, source: .appIntent)
        } catch {
            intentLog.error("LogExpense simpan gagal: \(String(describing: error), privacy: .public)")
            return .result(dialog: "Draft benar, tapi gagal menyimpan. Coba lagi dari dalam app.")
        }
        intentLog.info("LogExpense tersimpan")
        return .result(dialog: "Tercatat: \(DraftSummary.text(of: draft)).")
    }
}

struct RezekiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Catat pengeluaran di \(.applicationName)",
                "Log expense in \(.applicationName)"
            ],
            shortTitle: "Catat Pengeluaran",
            systemImageName: "wand.and.stars"
        )
        AppShortcut(
            intent: LogReceiptIntent(),
            phrases: [
                "Catat resi di \(.applicationName)",
                "Log receipt in \(.applicationName)"
            ],
            shortTitle: "Catat Resi",
            systemImageName: "doc.viewfinder"
        )
    }
}
