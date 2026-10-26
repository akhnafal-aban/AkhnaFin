import Foundation

public enum CurrencyFormatter {
    public static let indonesianLocale = Locale(identifier: "id_ID")

    public static func string(
        from amount: Decimal,
        currencyCode: String = "IDR",
        locale: Locale = indonesianLocale
    ) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }
}
