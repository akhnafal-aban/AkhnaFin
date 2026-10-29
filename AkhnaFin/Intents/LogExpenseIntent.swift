//
//  LogExpenseIntent.swift
//  AkhnaFin
//

import AppIntents
import OSLog
import AkhnaFinCore
import ServiceInterfaces
import Services

private let intentLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Intent")

struct LogExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Catat Pengeluaran"
    static let description = IntentDescription(
        "Catat transaksi dari satu kalimat Bahasa Inggris, mis. \"buy meatballs 20k at the canteen\"."
    )

    @Parameter(
        title: "Transaksi",
        requestValueDialog: "Apa yang mau dicatat? (Bahasa Inggris)"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let dependencies = AppContainer.dependencies
        intentLog.info("LogExpense mulai (\(text.count, privacy: .public) chars)")

        let pipeline = QuickLogPipeline(parser: dependencies.parser)
        let draft: TransactionDraft
        if #available(iOS 27, *) {
            draft = try await performBackgroundTask(options: []) { @Sendable in
                try await pipeline.parseDraft(from: text)
            }
        } else {
            draft = try await pipeline.parseDraft(from: text)
        }
        intentLog.info("LogExpense parse sukses")

        return stashAndPresentDraft(draft, source: .appIntent)
    }
}

@available(iOS 27, *)
extension LogExpenseIntent: LongRunningIntent {}

struct AkhnaFinShortcuts: AppShortcutsProvider {
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
