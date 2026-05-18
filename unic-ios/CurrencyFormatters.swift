import Foundation

private let _czkFormatter: NumberFormatter = {
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "CZK"
    fmt.maximumFractionDigits = 0
    return fmt
}()

private let _eurFormatter: NumberFormatter = {
    let fmt = NumberFormatter()
    fmt.numberStyle = .currency
    fmt.currencyCode = "EUR"
    fmt.maximumFractionDigits = 2
    return fmt
}()

extension Double {
    var czk: String {
        guard self > 0 else { return "—" }
        return _czkFormatter.string(from: NSNumber(value: self)) ?? "\(Int(self)) Kč"
    }
    var eur: String {
        guard self > 0 else { return "—" }
        return _eurFormatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f €", self)
    }
}
