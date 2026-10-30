//
//  LogReceiptIntent.swift
//  AkhnaFin
//

import AppIntents
import OSLog
import UniformTypeIdentifiers
import AkhnaFinCore
import Persistence
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

        let transaction: MoneyTransaction
        do {
            transaction = try dependencies.repository.commit(
                draft, source: .receipt, receiptImage: imageData
            )
        } catch {
            intentLog.error("LogReceipt commit gagal: \(String(describing: error), privacy: .public)")
            return .result(dialog: "Resi terbaca, tapi gagal menyimpan. Coba dari dalam app.")
        }

        if systemContext.currentMode.canContinueInForeground {
            try await continueInForeground("Periksa resinya di app", alwaysConfirm: false)
        }
        PendingDraftStore.requestEdit(transactionID: transaction.id, source: .receipt)
        return .result(dialog: "Resi tercatat. Detailnya bisa kamu ubah di app.")
    }
}

@available(iOS 27, *)
extension LogReceiptIntent: LongRunningIntent {}
