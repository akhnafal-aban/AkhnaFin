//
//  LogReceiptIntent.swift
//  AkhnaFin
//
//  Skenario: user selesai bayar → screenshot resi → Shortcut memicu intent ini →
//  OCR + heuristik mengisi draft → konfirmasi snippet DI LUAR APP (pola A3 yang
//  sama dgn LogExpenseIntent) → tersimpan + gambar resi ikut tercatat.
//

import AppIntents
import OSLog
import UniformTypeIdentifiers
import AkhnaFinCore
import ServiceInterfaces
import Services

private let intentLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Intent")

struct LogReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Receipt"
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
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let dependencies = AppContainer.dependencies
        let imageData = receipt.data
        intentLog.info("LogReceipt mulai (\(imageData.count, privacy: .public) bytes)")

        // Gambar langsung ke model multimodal (PLAN-006) dgn pagar waktu.
        // Gagal → lempar QuickLogError (LocalizedError): Siri menampilkan pesannya.
        let draft = try await QuickLogPipeline(parser: dependencies.parser)
            .parseReceiptDraft(fromImage: imageData)
        intentLog.info("LogReceipt parse sukses")

        // Snippet interaktif sebagai HASIL: tombol Simpan (commit + gambar)/Edit/Batal.
        return stashAndPresentDraft(draft, source: .receipt, receiptImage: imageData)
    }
}
