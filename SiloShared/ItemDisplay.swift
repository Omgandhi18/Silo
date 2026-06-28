import Foundation

/// Display helpers shared across the home cards, detail, and archive — kept in
/// one place so a "Saved link" fallback or a price format never drifts between
/// screens.
extension Item {
    var fallbackTitle: String {
        sourceDomain ?? url?.host() ?? "Saved link"
    }

    var displayTitle: String {
        title ?? fallbackTitle
    }

    var formattedPrice: String? {
        PriceFormatter.string(currentPrice ?? savedPrice, currencyCode: currencyCode)
    }

    var accessibilityLabel: String {
        [title ?? fallbackTitle, sourceDomain, formattedPrice]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

extension String {
    /// Trimmed text, or nil if it's blank — for collapsing empty form fields to
    /// optional model values.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
