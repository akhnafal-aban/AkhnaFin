import Foundation
import SwiftData
import AkhnaFinCore

public enum ModelContainerFactory {
    public enum StorageMode: Sendable {
        case cloudKit
        case localOnly
        case inMemory
    }

    public static func make(mode: StorageMode) throws -> ModelContainer {
        let schema = Schema([
            MoneyTransaction.self, TransactionCategory.self,
            DebtRecord.self, DebtPayment.self,
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
