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
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

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

        let pipeline = QuickLogPipeline(parser: dependencies.parser, scanner: dependencies.scanner)
        let draft: TransactionDraft
        if #available(iOS 27, *) {
            draft = try await performBackgroundTask(options: []) { @Sendable in
                try await pipeline.parseReceiptDraft(fromImage: imageData)
            }
        } else {
            draft = try await pipeline.parseReceiptDraft(fromImage: imageData)
        }
        intentLog.info("LogReceipt parse sukses")

        PendingDraftStore.stash(draft, source: .receipt, receiptImage: imageData)
        if systemContext.currentMode.canContinueInForeground {
            try await continueInForeground("Periksa resinya di app", alwaysConfirm: false)
        }
        PendingDraftStore.promoteStashToEditRequest()
        return .result(dialog: "Resi terbaca — periksa detailnya di app.")
    }
}

@available(iOS 27, *)
extension LogReceiptIntent: LongRunningIntent {}
