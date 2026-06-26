import Foundation

/// Pulls product metadata out of a raw HTML string.
///
/// No third-party HTML library here on purpose — we want a zero-dependency,
/// App-Store-clean target. Instead we lean on the two things stores reliably
/// emit for crawlers: schema.org JSON-LD and OpenGraph/meta tags. JSON-LD wins
/// when present (it's structured and carries real price data); OpenGraph fills
/// the gaps; the `<title>` tag is the last resort.
nonisolated struct HTMLMetadataParser {
    let html: String
    /// The page's final URL — used to resolve relative image paths and as the
    /// canonical fallback.
    let baseURL: URL

    func parse() -> ProductMetadata {
        var metadata = ProductMetadata(resolvedURLString: baseURL.absoluteString)

        let meta = MetaTags(html: html)
        let jsonLD = JSONLDProduct(html: html)

        // Title: JSON-LD name -> og:title -> twitter:title -> <title>
        metadata.title = (jsonLD?.name)
            ?? meta["og:title"]
            ?? meta["twitter:title"]
            ?? titleTag()

        // Image: JSON-LD image -> og:image -> twitter:image
        let imageString = jsonLD?.imageURLString
            ?? meta["og:image"]
            ?? meta["og:image:secure_url"]
            ?? meta["twitter:image"]
            ?? meta["twitter:image:src"]
        metadata.imageURL = imageString.flatMap { resolve($0) }

        // Price: JSON-LD offers -> product/og price meta
        if let offer = jsonLD?.offer {
            metadata.price = offer.price
            metadata.currencyCode = offer.currency
        }
        if metadata.price == nil {
            let priceString = meta["product:price:amount"]
                ?? meta["og:price:amount"]
                ?? meta["twitter:data1"]
            metadata.price = priceString.flatMap(Self.decimal(from:))
        }
        if metadata.currencyCode == nil {
            metadata.currencyCode = meta["product:price:currency"]
                ?? meta["og:price:currency"]
        }

        // Canonical: <link rel="canonical"> -> og:url -> resolved URL
        let declared = canonicalLink() ?? meta["og:url"]
        metadata.canonicalURLString = URLCanonicalizer.canonicalize(declared: declared, resolved: baseURL)

        metadata.sourceDomain = (metadata.canonicalURLString.flatMap(URL.init(string:))?.host())
            ?? baseURL.host()

        // og:site_name is often a nicer label than the bare host.
        if let siteName = meta["og:site_name"], metadata.sourceDomain == nil {
            metadata.sourceDomain = siteName
        }

        return metadata
    }

    private func resolve(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private func titleTag() -> String? {
        guard let raw = Self.firstGroup(in: html, pattern: "<title[^>]*>(.*?)</title>") else {
            return nil
        }
        return HTMLEntities.decode(raw).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func canonicalLink() -> String? {
        // Scan <link ...> tags for rel="canonical".
        let pattern = "<link\\b[^>]*>"
        for tag in Self.allMatches(in: html, pattern: pattern) {
            let attrs = AttributeScanner.attributes(in: tag)
            if attrs["rel"]?.lowercased() == "canonical", let href = attrs["href"] {
                return href
            }
        }
        return nil
    }

    // MARK: - Decimal parsing

    /// Stores write prices in maddening shapes: "1,299.00", "1.299,00", "$42",
    /// "USD 42.00". We pull the numeric core and normalise the decimal sep.
    static func decimal(from string: String) -> Decimal? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep digits, separators, and a leading minus.
        s = s.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !s.isEmpty else { return nil }

        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")

        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            // Whichever comes last is the decimal separator; the other is grouping.
            if comma > dot {
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        case (.some, nil):
            // Only commas. Treat as decimal sep if it looks like cents (",dd"),
            // otherwise as grouping.
            if let comma = lastComma, s.distance(from: comma, to: s.endIndex) <= 3 {
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        default:
            break
        }

        return Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Regex helpers

    static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[groupRange])
    }

    static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { r in String(text[r]) }
        }
    }
}

// MARK: - Meta tag index

/// One-pass index of every `<meta>` tag, keyed by its `property` or `name`.
nonisolated private struct MetaTags {
    private let table: [String: String]

    init(html: String) {
        var table: [String: String] = [:]
        for tag in HTMLMetadataParser.allMatches(in: html, pattern: "<meta\\b[^>]*>") {
            let attrs = AttributeScanner.attributes(in: tag)
            guard let content = attrs["content"] else { continue }
            // `property` (OpenGraph) or `name` (twitter, plain meta).
            if let key = attrs["property"] ?? attrs["name"] {
                let normalized = key.lowercased()
                // First writer wins — pages sometimes repeat tags.
                if table[normalized] == nil {
                    table[normalized] = HTMLEntities.decode(content)
                }
            }
        }
        self.table = table
    }

    subscript(_ key: String) -> String? {
        table[key]?.nilIfEmpty
    }
}

// MARK: - Attribute scanner

nonisolated private enum AttributeScanner {
    private static let regex = try? NSRegularExpression(
        pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')",
        options: []
    )

    /// Parses `key="value"` / `key='value'` pairs out of a single tag string.
    static func attributes(in tag: String) -> [String: String] {
        guard let regex else { return [:] }
        var result: [String: String] = [:]
        let range = NSRange(tag.startIndex..., in: tag)
        for match in regex.matches(in: tag, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let key = String(tag[keyRange]).lowercased()
            let valueRange = match.range(at: 3).location != NSNotFound
                ? match.range(at: 3)
                : match.range(at: 4)
            guard let vr = Range(valueRange, in: tag) else { continue }
            if result[key] == nil {
                result[key] = String(tag[vr])
            }
        }
        return result
    }
}

// MARK: - Minimal HTML entity decoding

nonisolated private enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "#39": "'", "#x27": "'", "#x2F": "/", "#47": "/"
    ]

    /// Good enough for titles and site names — handles the common named refs
    /// plus decimal/hex numeric refs. Not a full spec decoder.
    static func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = ""
        result.reserveCapacity(string.count)
        var buffer = ""        // entity body collected after an '&'
        var inEntity = false

        for char in string {
            if !inEntity {
                if char == "&" {
                    inEntity = true
                    buffer = ""
                } else {
                    result.append(char)
                }
                continue
            }

            switch char {
            case ";":
                // Closed entity: resolve it, or keep it verbatim if unknown.
                result += resolveEntity(buffer).map { $0 } ?? "&\(buffer);"
                inEntity = false
            case "&":
                // A new '&' before the previous entity closed — emit the stray one.
                result += "&\(buffer)"
                buffer = ""
            default:
                buffer.append(char)
                if buffer.count > 10 {
                    // Not a real entity — bail out and emit raw.
                    result += "&\(buffer)"
                    inEntity = false
                }
            }
        }

        if inEntity { result += "&\(buffer)" }
        return result
    }

    private static func resolveEntity(_ body: String) -> String? {
        if let named = named[body] { return named }
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            if let code = UInt32(body.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                return String(scalar)
            }
        } else if body.hasPrefix("#") {
            if let code = UInt32(body.dropFirst()), let scalar = Unicode.Scalar(code) {
                return String(scalar)
            }
        }
        return named[body.lowercased()]
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
