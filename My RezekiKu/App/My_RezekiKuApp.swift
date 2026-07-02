//
//  My_RezekiKuApp.swift
//  My RezekiKu
//

import SwiftUI
import SwiftData
import RezekiCore
import Persistence

@main
struct My_RezekiKuApp: App {
    private let container: ModelContainer
    private let dependencies: AppDependencies

    init() {
        container = Self.makeContainer()
        do {
            try CategorySeeder.seedIfNeeded(context: container.mainContext)
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
            do {
                return try ModelContainerFactory.make(mode: .localOnly)
            } catch {
                fatalError("Tidak bisa membuat ModelContainer: \(error)")
            }
        }
    }
}
