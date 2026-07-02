import SwiftUI
import RezekiCore

/// Picker kategori + subkategori. Caller menyuplai daftar (sudah difilter per jenis
/// transaksi); subkategori ditampilkan dengan nama induknya.
public struct CategoryPicker: View {
    private let title: String
    private let categories: [TransactionCategory]
    @Binding private var selection: TransactionCategory?

    public init(
        _ title: String = "Kategori",
        categories: [TransactionCategory],
        selection: Binding<TransactionCategory?>
    ) {
        self.title = title
        self.categories = categories
        self._selection = selection
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            Text("Tanpa Kategori").tag(TransactionCategory?.none)
            ForEach(categories) { category in
                Label(displayName(for: category), systemImage: category.iconName)
                    .tag(Optional(category))
            }
        }
    }

    private func displayName(for category: TransactionCategory) -> String {
        if let parent = category.parent {
            return "\(parent.name) › \(category.name)"
        }
        return category.name
    }
}
