import Foundation
import RezekiCore

extension [TransactionCategory] {
    /// Daftar siap-picker: kategori level atas se-`kind`, masing-masing diikuti
    /// subkategorinya terurut nama. Dipakai AddEdit & ConfirmDraft.
    func selectable(for kind: TransactionType) -> [TransactionCategory] {
        filter { $0.parent == nil && $0.kind == kind }
            .flatMap { [$0] + ($0.subcategories ?? []).sorted { $0.name < $1.name } }
    }
}
