//
//  RootView.swift
//  AkhnaFin
//

import SwiftUI
import OSLog
import AkhnaFinCore
import Persistence
import ServiceInterfaces

private let intentLogHandoff = Logger(subsystem: "com.aban.AkhnaFin", category: "Intent")

struct RootView: View {
    let dependencies: AppDependencies

    @Environment(\.scenePhase) private var scenePhase
    @State private var editHandoff: MoneyTransaction?

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
                SettingsView(
                    repository: dependencies.repository,
                    keyStore: dependencies.keyStore
                )
            }
        }
        .onAppear(perform: consumeEditRequest)
        .onChange(of: scenePhase) {
            if scenePhase == .active { consumeEditRequest() }
        }
        .sheet(item: $editHandoff) { transaction in
            TransactionFormView(
                mode: .edit(transaction),
                repository: dependencies.repository
            )
        }
    }

    private func consumeEditRequest() {
        guard let request = PendingDraftStore.consumeEditRequest() else { return }
        guard let transaction = try? dependencies.repository.fetchTransaction(id: request.transactionID) else {
            intentLogHandoff.error("Transaksi handoff tak ditemukan: \(request.transactionID)")
            return
        }
        editHandoff = transaction
    }
}
