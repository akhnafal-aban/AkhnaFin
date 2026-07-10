import SwiftUI
import AkhnaFinCore

/// Input nominal uang dengan format mata uang (default Rupiah, locale `id_ID`).
struct AmountField: View {
    private let title: String
    @Binding private var amount: Decimal
    private let currencyCode: String

    init(_ title: String = "Jumlah", amount: Binding<Decimal>, currencyCode: String = "IDR") {
        self.title = title
        self._amount = amount
        self.currencyCode = currencyCode
    }

    var body: some View {
        TextField(
            title,
            value: $amount,
            format: .currency(code: currencyCode).locale(CurrencyFormatter.indonesianLocale)
        )
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
    }
}
