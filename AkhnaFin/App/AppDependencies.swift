//
//  AppDependencies.swift
//  AkhnaFin
//
//  Composition root: merakit implementasi konkret di balik protokol AkhnaFinKit.
//  Pivot PLAN-006: stack AI = OpenRouter (Keychain key → client → parser 2-stage).
//

import SwiftData
import AkhnaFinCore
import ServiceInterfaces
import Services
import Persistence

@MainActor
final class AppDependencies {
    let repository: TransactionRepository
    let debtRepository: DebtRepository
    let signalRepository: SignalRepository
    let keyStore: any APIKeyStoring
    let parser: any TransactionParsing
    let locationService: any LocationCapturing = CoreLocationService()

    init(container: ModelContainer) {
        let context = container.mainContext
        repository = TransactionRepository(context: context)
        debtRepository = DebtRepository(context: context)
        signalRepository = SignalRepository(context: context)

        let keyStore = OpenRouterKeyStore()
        self.keyStore = keyStore

        // Nama kategori user disuntikkan ke instruksi generator agar saran nyambung;
        // personalisasi = knowledge-graph mini CategorySignal (PLAN-006).
        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        parser = OpenRouterParser(
            client: OpenRouterClient(keyStore: keyStore),
            keyStore: keyStore,
            categoryNames: categories.filter { $0.parent == nil }.map(\.name),
            subcategoryNames: categories.filter { $0.parent != nil }.map(\.name),
            personalization: SignalPersonalization(repository: signalRepository)
        )
    }
}
