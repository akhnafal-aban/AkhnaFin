//
//  AppDependencies.swift
//  AkhnaFin
//
//  Composition root: merakit implementasi konkret di balik protokol AkhnaFinKit.
//  Service berikutnya (speech, receipt, location) ditambahkan pada fasenya.
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
    let parser: any TransactionParsing
    let scanner: any ReceiptScanning = VisionReceiptScanner()
    let locationService: any LocationCapturing = CoreLocationService()

    init(container: ModelContainer) {
        let context = container.mainContext
        repository = TransactionRepository(context: context)
        debtRepository = DebtRepository(context: context)

        // Nama kategori user disuntikkan ke instruksi parser agar saran kategorinya nyambung.
        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        parser = FoundationModelsParser(
            categoryNames: categories.filter { $0.parent == nil }.map(\.name),
            subcategoryNames: categories.filter { $0.parent != nil }.map(\.name)
        )
    }
}
