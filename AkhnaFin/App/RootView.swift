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
            Tab("Dashboard", systemImage: "chart.pie") {
                DashboardView(debtRepository: dependencies.debtRepository)
            }
            Tab("Transaksi", systemImage: "list.bullet.rectangle") {
                TransactionListView(
                    repository: dependencies.repository,
                    parser: dependencies.parser,
                    scanner: dependencies.scanner,
                    locationService: dependencies.locationService
                )
            }
            Tab("Pengaturan", systemImage: "gearshape") {
                SettingsView(repository: dependencies.repository)
            }
        }
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
        guard let pending = PendingDraftStore.consumeEditRequest() else {
            return
        }
        handoffDraft = HandoffDraft(
            draft: pending.draft,
            receiptImage: pending.receiptImage,
            source: pending.source
        )
        PendingDraftStore.clearStash()
    }
}

private struct HandoffDraft: Identifiable {
    let id = UUID()
    let draft: TransactionDraft
    let receiptImage: Data?
    let source: EntrySource
}
