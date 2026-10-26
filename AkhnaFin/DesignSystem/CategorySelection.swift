import Foundation
import AkhnaFinCore

extension [TransactionCategory] {
    func selectable(for kind: TransactionType) -> [TransactionCategory] {
        filter { $0.parent == nil && $0.kind == kind }
            .flatMap { [$0] + ($0.subcategories ?? []).sorted { $0.name < $1.name } }
    }
}
