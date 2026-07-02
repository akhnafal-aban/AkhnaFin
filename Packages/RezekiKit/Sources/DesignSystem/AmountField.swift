import SwiftUI
import RezekiCore

/// Input nominal uang dengan format mata uang (default Rupiah, locale `id_ID`).
public struct AmountField: View {
    private let title: String
    @Binding private var amount: Decimal
    private let currencyCode: String

    public init(_ title: String = "Jumlah", amount: Binding<Decimal>, currencyCode: String = "IDR") {
        self.title = title
        self._amount = amount
        self.currencyCode = currencyCode
    }

    public var body: some View {
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
