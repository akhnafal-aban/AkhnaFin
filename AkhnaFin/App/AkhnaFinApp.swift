//
//  AkhnaFinApp.swift
//  AkhnaFin
//

import SwiftUI
import SwiftData
import AkhnaFinCore

@main
struct AkhnaFinApp: App {
    private let container: ModelContainer
    private let dependencies: AppDependencies

    init() {
        container = AppContainer.shared
        dependencies = AppContainer.dependencies
        #if DEBUG
        seedDemoDataIfRequested()
        #endif
    }

    #if DEBUG
    /// Data dummy untuk verifikasi visual di simulator (dashboard butuh isi;
    /// simctl tak bisa tap). Aktif HANYA bila env `AKHNAFIN_DEMO_SEED=1` dan
    /// store masih kosong — tak pernah menyentuh build Release.
    @MainActor
    private func seedDemoDataIfRequested() {
        guard ProcessInfo.processInfo.environment["AKHNAFIN_DEMO_SEED"] == "1" else { return }
        let context = container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<MoneyTransaction>())) ?? 0) == 0 else { return }
        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        let calendar = Calendar.current
        for offset in 0..<24 {
            let type: TransactionType = offset % 8 == 7 ? .income : .expense
            // Kategori WAJIB se-jenis: expense tak boleh kena Gaji/Bonus (income),
            // dan sebaliknya — kalau tidak, demo dashboard tampil ngawur.
            let sameKind = categories.filter { $0.kind == type }
            let transaction = MoneyTransaction(
                amount: Decimal((offset % 7 + 1) * 8500),
                type: type,
                date: calendar.date(byAdding: .day, value: -(offset % 27), to: .now)!,
                note: "Demo \(offset)",
                source: .manual,
                category: sameKind.isEmpty ? nil : sameKind[offset % sameKind.count]
            )
            context.insert(transaction)
        }
        // Hutang dummy: paylater terlambat, piutang teman, satu lunas.
        let paylater = DebtRecord(
            counterparty: "SPayLater", direction: .iOwe, principal: 750_000,
            dueDate: calendar.date(byAdding: .day, value: -3, to: .now)
        )
        let friend = DebtRecord(counterparty: "Budi", direction: .owedToMe, principal: 150_000)
        let settled = DebtRecord(counterparty: "GoPayLater", direction: .iOwe, principal: 90_000)
        for record in [paylater, friend, settled] { context.insert(record) }
        let installment = DebtPayment(amount: 250_000, note: "Cicilan 1")
        installment.debt = paylater
        context.insert(installment)
        let payoff = DebtPayment(amount: 90_000, note: "Pelunasan")
        payoff.debt = settled
        context.insert(payoff)
        try? context.save()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
        .modelContainer(container)
    }
}
