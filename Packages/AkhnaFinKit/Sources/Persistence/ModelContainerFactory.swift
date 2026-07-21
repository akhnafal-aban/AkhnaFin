import Foundation
import SwiftData
import AkhnaFinCore

/// Membuat `ModelContainer` dengan mode penyimpanan eksplisit.
public enum ModelContainerFactory {
    public enum StorageMode: Sendable {
        /// Persisten + sinkronisasi CloudKit (butuh entitlement iCloud di app target).
        case cloudKit
        /// Persisten lokal tanpa CloudKit.
        case localOnly
        /// In-memory — untuk unit test & SwiftUI Preview (CloudKit tak bisa jalan tanpa entitlement).
        case inMemory
    }

    public static func make(mode: StorageMode) throws -> ModelContainer {
        let schema = Schema([
            MoneyTransaction.self, TransactionCategory.self,
            DebtRecord.self, DebtPayment.self,
            CategorySignal.self,
        ])
        let configuration: ModelConfiguration
        switch mode {
        case .cloudKit:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        case .localOnly:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        case .inMemory:
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
