//
//  AppDependencies.swift
//  My RezekiKu
//
//  Composition root: merakit implementasi konkret di balik protokol RezekiKit.
//  Service berikutnya (speech, receipt, location) ditambahkan pada fasenya.
//

import SwiftData
import RezekiCore
import ServiceInterfaces
import Services
import Persistence

@MainActor
final class AppDependencies {
    let repository: TransactionRepository
    let parser: any TransactionParsing

    init(container: ModelContainer) {
        let context = container.mainContext
        repository = TransactionRepository(context: context)

        // Nama kategori user disuntikkan ke instruksi parser agar saran kategorinya nyambung.
        let categories = (try? context.fetch(FetchDescriptor<TransactionCategory>())) ?? []
        parser = FoundationModelsParser(
            categoryNames: categories.filter { $0.parent == nil }.map(\.name),
            subcategoryNames: categories.filter { $0.parent != nil }.map(\.name)
        )
    }
}
