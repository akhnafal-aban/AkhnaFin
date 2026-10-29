//
//  AppDependencies.swift
//  AkhnaFin
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
    let keyStore: any APIKeyStoring
    let parser: any TransactionParsing
    let scanner: any ReceiptScanning = VisionReceiptScanner()
    let locationService: any LocationCapturing = CoreLocationService()

    init(container: ModelContainer) {
        let context = container.mainContext
        repository = TransactionRepository(context: context)
        debtRepository = DebtRepository(context: context)

        let keyStore = InferenceKeyStore()
        self.keyStore = keyStore

        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        parser = GLMTransactionParser(
            client: InferenceClient(keyStore: keyStore),
            keyStore: keyStore,
            categoryNames: categories.filter { $0.parent == nil }.map(\.name),
            subcategoryNames: categories.filter { $0.parent != nil }.map(\.name)
        )
    }
}
