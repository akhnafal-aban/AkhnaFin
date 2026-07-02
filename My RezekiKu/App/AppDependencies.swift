//
//  AppDependencies.swift
//  My RezekiKu
//
//  Composition root: merakit implementasi konkret di balik protokol RezekiKit.
//  Service AI (parsing, speech, receipt, location) ditambahkan di fase berikutnya.
//

import SwiftData
import Persistence

@MainActor
final class AppDependencies {
    let repository: TransactionRepository

    init(container: ModelContainer) {
        repository = TransactionRepository(context: container.mainContext)
    }
}
