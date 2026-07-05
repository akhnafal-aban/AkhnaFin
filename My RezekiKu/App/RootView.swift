//
//  RootView.swift
//  My RezekiKu
//

import SwiftUI
import RezekiCore
import ServiceInterfaces

struct RootView: View {
    let dependencies: AppDependencies

    @Environment(\.scenePhase) private var scenePhase
    @State private var handoffDraft: HandoffDraft?

    var body: some View {
        TabView {
            Tab("Transaksi", systemImage: "list.bullet.rectangle") {
                TransactionListView(repository: dependencies.repository)
            }
            Tab("Catat Cepat", systemImage: "wand.and.stars") {
                QuickAddView(parser: dependencies.parser, repository: dependencies.repository)
            }
            Tab("Pengaturan", systemImage: "gearshape") {
                SettingsPlaceholderView()
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
                mode: .confirmDraft(handoff.draft, source: .appIntent),
                repository: dependencies.repository
            )
        }
    }

    private func consumeEditRequest() {
        if let draft = PendingDraftStore.consumeEditRequest() {
            handoffDraft = HandoffDraft(draft: draft)
        }
    }
}

private struct HandoffDraft: Identifiable {
    let id = UUID()
    let draft: TransactionDraft
}

/// Placeholder — diganti SettingsFeature (kelola kategori, izin, status iCloud) pada fasenya.
private struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Versi", value: "1.0")
                    LabeledContent("Penyimpanan", value: "iCloud")
                } header: {
                    Text("Tentang")
                }
            }
            .navigationTitle("Pengaturan")
        }
    }
}
