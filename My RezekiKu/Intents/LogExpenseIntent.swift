//
//  LogExpenseIntent.swift
//  My RezekiKu
//
//  Siri/Shortcuts/Spotlight/Action Button → catat transaksi dari satu kalimat.
//  Wajib di app bundle. Hasil AI DIKONFIRMASI dulu sebelum commit (aturan pipeline).
//

import AppIntents
import RezekiCore
import ServiceInterfaces
import Persistence

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
        let dependencies = AppDependencies(container: AppContainer.make())

        let draft = try await dependencies.parser.parse(text)

        // Konfirmasi-dulu: hasil AI tak pernah langsung tersimpan.
        try await requestConfirmation(dialog: "Catat \(Self.summary(of: draft))?")

        _ = try dependencies.repository.commit(draft, source: .appIntent)
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
