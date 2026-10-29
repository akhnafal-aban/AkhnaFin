//
//  LogReceiptIntent.swift
//  AkhnaFin
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

        let draft = try await QuickLogPipeline(
            parser: dependencies.parser,
            scanner: dependencies.scanner
        ).parseReceiptDraft(fromImage: imageData)
        intentLog.info("LogReceipt parse sukses")

        return stashAndPresentDraft(draft, source: .receipt, receiptImage: imageData)
    }
}
