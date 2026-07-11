//
//  AppContainer.swift
//  AkhnaFin
//
//  Pembangun ModelContainer bersama — dipakai app (AkhnaFinApp) DAN App Intent
//  (LogExpenseIntent bisa jalan di proses terpisah saat app tidak aktif).
//

import SwiftData
import AkhnaFinCore
import Persistence
import os

enum AppContainer {
    private static let logger = Logger(subsystem: "com.aban.AkhnaFin", category: "Persistence")

    /// Mode penyimpanan yang benar-benar aktif (di-set saat container dibangun) —
    /// dibaca Settings untuk menampilkan status sync. Valid setelah `shared` diakses.
    @MainActor
    private(set) static var activeStorageMode: ModelContainerFactory.StorageMode = .cloudKit

    /// Container tunggal per proses (BUG-2a): init CloudKit + seed + dedupe hanya
    /// SEKALI — invocation intent berikutnya memakai instance yang sama, bukan
    /// membangun ulang. `static let` = lazy & thread-safe.
    @MainActor
    static let shared: ModelContainer = make()

    /// Wiring dependencies tunggal per proses — dipakai app & intent.
    @MainActor
    static let dependencies = AppDependencies(container: shared)

    /// CloudKit dulu; bila gagal (mis. belum login iCloud) jatuh ke lokal agar app tetap jalan.
    /// Sekaligus seed + dedupe kategori (idempotent).
    @MainActor
    private static func make() -> ModelContainer {
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
