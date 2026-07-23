//
//  RootView.swift
//  AkhnaFin
//

import SwiftUI
import AkhnaFinCore
import ServiceInterfaces

struct RootView: View {
    let dependencies: AppDependencies

    @Environment(\.scenePhase) private var scenePhase
    @State private var handoffDraft: HandoffDraft?

    var body: some View {
        TabView {
            // Tab "Catat Cepat" dihapus (keputusan Fase C): semua jalur capture
            // pindah ke menu "+" di Transaksi (HIG pull-down button).
            Tab("Dashboard", systemImage: "chart.pie") {
                DashboardView(debtRepository: dependencies.debtRepository)
            }
            Tab("Transaksi", systemImage: "list.bullet.rectangle") {
                TransactionListView(
                    repository: dependencies.repository,
                    parser: dependencies.parser,
                    locationService: dependencies.locationService,
                    signalRepository: dependencies.signalRepository,
                    debtRepository: dependencies.debtRepository
                )
            }
            Tab("Pengaturan", systemImage: "gearshape") {
                SettingsView(
                    repository: dependencies.repository,
                    keyStore: dependencies.keyStore,
                    modelPreferenceStore: dependencies.modelPreferenceStore,
                    modelCatalog: dependencies.modelCatalog
                )
            }
        }
        // Jalur "Edit di App" dari snippet intent (A3): konsumsi draft handoff
        // saat app aktif → sajikan layar konfirmasi prefilled.
        .onAppear(perform: consumeEditRequest)
        .onChange(of: scenePhase) {
            if scenePhase == .active { consumeEditRequest() }
        }
        .sheet(item: $handoffDraft) { handoff in
            TransactionFormView(
                mode: .confirmDraft(handoff.draft, source: handoff.source, receiptImage: handoff.receiptImage),
                repository: dependencies.repository,
                locationService: dependencies.locationService,
                signalRepository: dependencies.signalRepository
            )
        }
    }

    private func consumeEditRequest() {
        guard let pending = PendingDraftStore.consumeEditRequest() else {
            // Tidak ada edit-request → mungkin ADA konfirmasi Siri berjalan (mis.
            // app di-foreground saat snippet menimpa). JANGAN sentuh slot confirming:
            // menghapusnya akan mencuri draft yang sedang dikonfirmasi (review #5).
            // Slot yang batal bersifat inert (hanya dibaca saat konfirmasi aktif)
            // dan akan ditimpa stash berikutnya.
            return
        }
        handoffDraft = HandoffDraft(
            draft: pending.draft,
            receiptImage: pending.receiptImage,
            source: pending.source
        )
        // promoteStashToEditRequest sudah menyalin slot confirming ke edit-request,
        // jadi aman membersihkannya sekarang.
        PendingDraftStore.clearStash()
    }
}

private struct HandoffDraft: Identifiable {
    let id = UUID()
    let draft: TransactionDraft
    let receiptImage: Data?
    let source: EntrySource
}
