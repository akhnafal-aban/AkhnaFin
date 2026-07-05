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

        // Konfirmasi-dulu: hasil AI tak pernah langsung tersimpan.
        // (Pembatalan user melempar error sistem — biarkan menyebar, jangan ditelan.)
        try await requestConfirmation(dialog: "Catat \(Self.summary(of: draft))?")

        do {
            _ = try dependencies.repository.commit(draft, source: .appIntent)
        } catch {
            intentLog.error("LogExpense simpan gagal: \(String(describing: error), privacy: .public)")
            return .result(dialog: "Draft benar, tapi gagal menyimpan. Coba lagi dari dalam app.")
        }
        intentLog.info("LogExpense tersimpan")
        return .result(dialog: "Tercatat: \(Self.summary(of: draft)).")
    }

    private static func summary(of draft: TransactionDraft) -> String {
        let amount = CurrencyFormatter.string(from: draft.amount)
        let label = [draft.merchant, draft.note].first { !$0.isEmpty } ?? draft.categoryName
        return label.isEmpty ? amount : "\(amount) — \(label)"
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
    }
}
