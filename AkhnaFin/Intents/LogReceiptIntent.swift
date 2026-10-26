//
//  LogReceiptIntent.swift
//  AkhnaFin
//
//  Screenshot resi → model multimodal (PLAN-006) → draft → konfirmasi snippet
//  di luar app — pola sama dengan LogExpenseIntent. Gambar resi ikut tersimpan.
//

import AppIntents
import OSLog
import UniformTypeIdentifiers
import AkhnaFinCore
import ServiceInterfaces
import Services

private let intentLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Intent")

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
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let dependencies = AppContainer.dependencies
        let imageData = receipt.data
        intentLog.info("LogReceipt mulai (\(imageData.count, privacy: .public) bytes)")

        // OCR + heuristik dgn pagar waktu — pipeline yang sama dgn jalur kalimat.
        // Gagal → lempar QuickLogError (LocalizedError): Siri menampilkan pesannya.
        let draft = try await QuickLogPipeline(
            parser: dependencies.parser,
            scanner: dependencies.scanner
        ).parseReceiptDraft(fromImage: imageData)
        intentLog.info("LogReceipt parse sukses")

        // Snippet interaktif sebagai HASIL: tombol Simpan (commit + gambar)/Edit/Batal.
        return stashAndPresentDraft(draft, source: .receipt, receiptImage: imageData)
    }
}
