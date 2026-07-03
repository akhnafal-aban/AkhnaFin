//
//  My_RezekiKuApp.swift
//  My RezekiKu
//

import SwiftUI
import SwiftData
import RezekiCore
import Persistence
import os

@main
struct My_RezekiKuApp: App {
    private static let logger = Logger(subsystem: "com.aban.My-RezekiKu", category: "Persistence")

    private let container: ModelContainer
    private let dependencies: AppDependencies

    init() {
        container = Self.makeContainer()
        do {
            try CategorySeeder.seedIfNeeded(context: container.mainContext)
            // Konvergensi multi-device: gabungkan built-in dobel setelah import CloudKit tiba.
            try CategorySeeder.dedupeIfNeeded(context: container.mainContext)
        } catch {
            assertionFailure("Seeding kategori gagal: \(error)")
        }
        dependencies = AppDependencies(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
        .modelContainer(container)
    }

    /// CloudKit dulu; bila gagal (mis. belum login iCloud) jatuh ke lokal agar app tetap jalan.
    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainerFactory.make(mode: .cloudKit)
        } catch {
            logger.error("Container CloudKit gagal, fallback ke penyimpanan lokal (sync NONAKTIF): \(String(describing: error), privacy: .public)")
            do {
                return try ModelContainerFactory.make(mode: .localOnly)
            } catch {
                fatalError("Tidak bisa membuat ModelContainer: \(error)")
            }
        }
    }
}
