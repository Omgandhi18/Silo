import Foundation

/// Everything we manage to scrape about a product, in a form that can cross
/// actor boundaries safely. The coordinator decides which fields actually land
/// on the `Item` — this is just the raw harvest.
nonisolated struct ProductMetadata: Sendable {
    var title: String?
    var sourceDomain: String?
    var imageURL: URL?
    var price: Decimal?
    var currencyCode: String?

    /// The URL after redirects were followed (what the user effectively landed on).
    var resolvedURLString: String?
    /// Tracking-stripped, deduplication-friendly URL.
    var canonicalURLString: String?

    /// True once we've found anything worth saving. An all-nil harvest still
    /// flips the item to `.enriched` so we don't re-fetch forever, but the
    /// coordinator can use this to decide how loudly to fail.
    var hasContent: Bool {
        title != nil || imageURL != nil || price != nil
    }
}
