import Foundation

/// Memformat nilai uang menjadi string terlokalisasi (default Rupiah / `id_ID`).
public enum CurrencyFormatter {
    public static let indonesianLocale = Locale(identifier: "id_ID")

    /// Contoh: `20000` → `"Rp20.000,00"` pada locale `id_ID`.
    public static func string(
        from amount: Decimal,
        currencyCode: String = "IDR",
        locale: Locale = indonesianLocale
    ) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }
}
