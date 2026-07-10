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
                mode: .confirmDraft(handoff.draft, source: handoff.source, receiptImage: handoff.receiptImage),
                repository: dependencies.repository
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
