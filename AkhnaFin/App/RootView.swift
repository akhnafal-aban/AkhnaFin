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
            Tab("Transaksi", systemImage: "list.bullet.rectangle") {
                TransactionListView(
                    repository: dependencies.repository,
                    locationService: dependencies.locationService
                )
            }
            Tab("Catat Cepat", systemImage: "wand.and.stars") {
                QuickAddView(
                    parser: dependencies.parser,
                    repository: dependencies.repository,
                    locationService: dependencies.locationService
                )
            }
            Tab("Pengaturan", systemImage: "gearshape") {
                SettingsView(repository: dependencies.repository)
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
                locationService: dependencies.locationService
            )
        }
    }

    private func consumeEditRequest() {
        if let pending = PendingDraftStore.consumeEditRequest() {
            handoffDraft = HandoffDraft(
                draft: pending.draft,
                receiptImage: pending.receiptImage,
                source: pending.source
            )
        }
        // App di depan → tak ada konfirmasi Siri berjalan; buang sisa slot
        // confirming yang tak jadi di-commit (intent batal tak lagi menghapusnya).
        PendingDraftStore.clearStash()
    }
}

private struct HandoffDraft: Identifiable {
    let id = UUID()
    let draft: TransactionDraft
    let receiptImage: Data?
    let source: EntrySource
}
