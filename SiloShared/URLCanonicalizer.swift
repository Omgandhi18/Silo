import Foundation

/// Turns a messy, share-sheet URL into a stable identity we can dedupe on.
///
/// We're deliberately conservative: we strip the well-known tracking junk
/// (utm_*, click ids, share ids) and normalise host/fragment, but we keep any
/// query param we don't recognise, because for plenty of stores the product id
/// *lives* in the query string (`?sku=`, `?variant=`, ...). Throwing those away
/// would merge genuinely different products.
nonisolated enum URLCanonicalizer {

    /// Query keys that never identify a product — pure attribution/analytics.
    private static let trackingKeys: Set<String> = [
        "fbclid", "gclid", "dclid", "gclsrc", "msclkid", "yclid",
        "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi",
        "ref", "ref_src", "ref_url", "referrer", "source", "share",
        "spm", "scm", "_branch_match_id", "vero_id", "wickedid"
    ]

    /// Prefixes whose entire family is tracking (utm_source, utm_medium, ...).
    private static let trackingPrefixes = ["utm_", "pk_", "piwik_"]

    static func canonicalize(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        // Drop a leading "www." so m.site / www.site / site collapse together is
        // *not* done here — different subdomains can be different stores. We only
        // lowercase. Host equality stays strict on purpose.

        if let items = components.queryItems {
            let kept = items.filter { !isTracking($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }

        // Normalise a trailing slash on the path so "/p/123" and "/p/123/" match.
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }

        return components.url?.absoluteString ?? url.absoluteString
    }

    /// Picks the best canonical URL when the page advertises its own (via
    /// `<link rel="canonical">` or `og:url`), falling back to the resolved URL.
    static func canonicalize(declared: String?, resolved: URL) -> String {
        if let declared,
           let declaredURL = URL(string: declared),
           declaredURL.scheme != nil,
           declaredURL.host != nil {
            return canonicalize(declaredURL)
        }
        return canonicalize(resolved)
    }

    private static func isTracking(_ key: String) -> Bool {
        let lower = key.lowercased()
        if trackingKeys.contains(lower) { return true }
        return trackingPrefixes.contains { lower.hasPrefix($0) }
    }
}
