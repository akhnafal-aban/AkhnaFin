//
//  AppContainer.swift
//  My RezekiKu
//
//  Pembangun ModelContainer bersama — dipakai app (My_RezekiKuApp) DAN App Intent
//  (LogExpenseIntent bisa jalan di proses terpisah saat app tidak aktif).
//

import SwiftData
import RezekiCore
import Persistence
import os

enum AppContainer {
    private static let logger = Logger(subsystem: "com.aban.My-RezekiKu", category: "Persistence")

    /// CloudKit dulu; bila gagal (mis. belum login iCloud) jatuh ke lokal agar app tetap jalan.
    /// Sekaligus seed + dedupe kategori (idempotent).
    @MainActor
    static func make() -> ModelContainer {
        let container = makeContainer()
        do {
            try CategorySeeder.seedIfNeeded(context: container.mainContext)
            // Konvergensi multi-device: gabungkan built-in dobel setelah import CloudKit tiba.
            try CategorySeeder.dedupeIfNeeded(context: container.mainContext)
        } catch {
            assertionFailure("Seeding kategori gagal: \(error)")
        }
        return container
    }

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
