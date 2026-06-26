import Foundation

/// Formats prices the way the cards and detail screen both want them: the item's
/// own currency, and no trailing ".00" on whole amounts (₹129, not ₹129.00).
nonisolated enum PriceFormatter {
    static func string(_ price: Decimal?, currencyCode: String?) -> String? {
        guard let price else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode ?? defaultCurrencyCode
        formatter.maximumFractionDigits = price.isWholeNumber ? 0 : 2

        return formatter.string(from: price as NSDecimalNumber)
    }

    /// The user's chosen default (from Settings), falling back to the device
    /// locale's currency.
    static var defaultCurrencyCode: String? {
        UserDefaults.standard.string(forKey: AppConstants.defaultCurrencyKey)
            ?? Locale.current.currency?.identifier
    }
}

extension Decimal {
    nonisolated var isWholeNumber: Bool {
        self == rounded()
    }

    nonisolated func rounded() -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 0, .plain)
        return result
    }
}
