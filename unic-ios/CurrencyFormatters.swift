import Foundation

/// Shared `NumberFormatter` for Czech Koruna (CZK), zero decimal places.
private let _czkFormatter: NumberFormatter = {
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "CZK"
    fmt.maximumFractionDigits = 0
    return fmt
}()

/// Shared `NumberFormatter` for Euro (EUR), two decimal places.
private let _eurFormatter: NumberFormatter = {
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "EUR"
    fmt.maximumFractionDigits = 2
    return fmt
}()

extension Double {
    /// Formats the receiver as a Czech Koruna string (e.g. `"1 500 Kč"`).
    /// Returns `"—"` for zero or negative values.
    var czk: String {
        guard self > 0 else { return "—" }
        return _czkFormatter.string(from: NSNumber(value: self)) ?? "\(Int(self)) Kč"
    }

    /// Formats the receiver as a Euro string (e.g. `"12.50 €"`).
    /// Returns `"—"` for zero or negative values.
    var eur: String {
        guard self > 0 else { return "—" }
        return _eurFormatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f €", self)
    }
}
