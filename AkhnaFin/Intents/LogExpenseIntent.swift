//
//  LogExpenseIntent.swift
//  AkhnaFin
//
//  Siri/Shortcuts/Spotlight/Action Button → catat transaksi dari satu kalimat.
//  Wajib di app bundle. Hasil AI DIKONFIRMASI dulu sebelum commit (aturan pipeline).
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
        "Catat transaksi dari satu kalimat, mis. \"beli bakso 20k di kantin\"."
    )
    // Jalan di background (tanpa buka app); konfirmasi muncul sebagai prompt Siri/Shortcuts.
    static let openAppWhenRun = false

    @Parameter(
        title: "Transaksi",
        requestValueDialog: "Apa yang mau dicatat?"
    )
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Container & wiring dibangun sekali per proses (BUG-2a) — bukan per invocation.
        let dependencies = AppContainer.dependencies
        intentLog.info("LogExpense mulai (\(text.count, privacy: .public) chars)")

        // Parse dengan pagar waktu — error granular, tidak pernah stuck (BUG-2b).
        // Gagal → lempar QuickLogError (LocalizedError): Siri menampilkan pesannya.
        let draft = try await QuickLogPipeline(parser: dependencies.parser).parseDraft(from: text)
        intentLog.info("LogExpense parse sukses")

        // Snippet interaktif sebagai HASIL: tombol Simpan/Edit/Batal yang menutup.
        return stashAndPresentDraft(draft, source: .appIntent)
    }
}

struct AkhnaFinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogExpenseIntent(),
            phrases: [
                "Catat pengeluaran di \(.applicationName)",
                "Log expense in \(.applicationName)"
            ],
            shortTitle: "Text Entry",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: LogReceiptIntent(),
            phrases: [
                "Catat resi di \(.applicationName)",
                "Log receipt in \(.applicationName)"
            ],
            shortTitle: "Scan Receipt",
            systemImageName: "doc.viewfinder"
        )
    }
}
