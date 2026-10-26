//
//  AppContainer.swift
//  AkhnaFin
//

import SwiftData
import AkhnaFinCore
import Persistence
import os

enum AppContainer {
    private static let logger = Logger(subsystem: "com.aban.AkhnaFin", category: "Persistence")

    @MainActor
    private(set) static var activeStorageMode: ModelContainerFactory.StorageMode = .cloudKit

    @MainActor
    static let shared: ModelContainer = make()

    @MainActor
    static let dependencies = AppDependencies(container: shared)

    @MainActor
    private static func make() -> ModelContainer {
        let container = makeContainer()
        do {
            try CategorySeeder.seedIfNeeded(context: container.mainContext)
            try CategorySeeder.dedupeIfNeeded(context: container.mainContext)
        } catch {
            logger.error("Seeding kategori gagal: \(String(describing: error), privacy: .public)")
            assertionFailure("Seeding kategori gagal: \(error)")
        }
        return container
    }

    @MainActor
    private static func makeContainer() -> ModelContainer {
        do {
            let container = try ModelContainerFactory.make(mode: .cloudKit)
            activeStorageMode = .cloudKit
            return container
        } catch {
            logger.error("Container CloudKit gagal, fallback ke penyimpanan lokal (sync NONAKTIF): \(String(describing: error), privacy: .public)")
            do {
                let container = try ModelContainerFactory.make(mode: .localOnly)
                activeStorageMode = .localOnly
                return container
            } catch {
                fatalError("Tidak bisa membuat ModelContainer: \(error)")
            }
        }
    }
}
