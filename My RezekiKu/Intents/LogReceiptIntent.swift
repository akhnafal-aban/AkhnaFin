//
//  LogReceiptIntent.swift
//  My RezekiKu
//
//  Skenario: user selesai bayar → screenshot resi → Shortcut memicu intent ini →
//  OCR + heuristik mengisi draft → konfirmasi snippet DI LUAR APP (pola A3 yang
//  sama dgn LogExpenseIntent) → tersimpan + gambar resi ikut tercatat.
//

import AppIntents
import OSLog
import UniformTypeIdentifiers
import RezekiCore
import ServiceInterfaces
import Services
import Persistence

private let intentLog = Logger(subsystem: "com.aban.My-RezekiKu", category: "Intent")

struct LogReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Catat Resi"
    static let description = IntentDescription(
        "Analisis screenshot resi lalu catat transaksinya. Sambungkan dengan aksi \"Take Screenshot\" di Shortcuts."
    )
    static let openAppWhenRun = false

    @Parameter(
        title: "Gambar Resi",
        description: "Screenshot atau foto resi yang akan dianalisis.",
        supportedContentTypes: [.image]
    )
    var receipt: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dependencies = AppContainer.dependencies
        let imageData = receipt.data
        intentLog.info("LogReceipt mulai (\(imageData.count, privacy: .public) bytes)")

        // OCR + heuristik dgn pagar waktu — pipeline yang sama dgn jalur kalimat.
        let draft: TransactionDraft
        do {
            draft = try await QuickLogPipeline(
                parser: dependencies.parser,
                scanner: dependencies.scanner
            ).parseReceiptDraft(fromImage: imageData)
            intentLog.info("LogReceipt parse sukses")
        } catch let error as QuickLogError {
            intentLog.error("LogReceipt parse gagal: \(String(describing: error), privacy: .public)")
            return .result(dialog: "\(error.errorDescription ?? "Gagal membaca resi.")")
        }

        // Konfirmasi-dulu di luar app: snippet ringkasan + jalur Edit di App (A3).
        PendingDraftStore.stash(draft, source: .receipt, receiptImage: imageData)
        do {
            try await requestConfirmation(
                dialog: "Catat \(DraftSummary.text(of: draft))?",
                snippetIntent: ConfirmExpenseSnippetIntent()
            )
        } catch {
            // JANGAN clearStash di sini (race dgn "Edit di App"): lihat catatan
            // di LogExpenseIntent. Slot ditimpa stash berikutnya; sukses commit
            // tetap membersihkannya di bawah.
            intentLog.info("LogReceipt konfirmasi dibatalkan")
            throw error
        }
        PendingDraftStore.clearStash()

        do {
            _ = try dependencies.repository.commit(draft, source: .receipt, receiptImage: imageData)
        } catch {
            intentLog.error("LogReceipt simpan gagal: \(String(describing: error), privacy: .public)")
            return .result(dialog: "Draft benar, tapi gagal menyimpan. Coba lagi dari dalam app.")
        }
        intentLog.info("LogReceipt tersimpan")
        return .result(dialog: "Tercatat: \(DraftSummary.text(of: draft)).")
    }
}
