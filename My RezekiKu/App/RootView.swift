//
//  RootView.swift
//  My RezekiKu
//

import SwiftUI
import TransactionsFeature

struct RootView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            Tab("Transaksi", systemImage: "list.bullet.rectangle") {
                TransactionListView(repository: dependencies.repository)
            }
            Tab("Pengaturan", systemImage: "gearshape") {
                SettingsPlaceholderView()
            }
        }
    }
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
