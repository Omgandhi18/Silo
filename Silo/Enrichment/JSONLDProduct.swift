import Foundation

/// Extracts a schema.org `Product` node from a page's JSON-LD blocks.
///
/// Real-world JSON-LD is a swamp: a page may ship several `<script type=
/// "application/ld+json">` blocks, each holding an object, an array, or a
/// `{"@graph": [...]}` wrapper, with `@type` as a string *or* an array. We walk
/// every block recursively and grab the first node that smells like a Product.
nonisolated struct JSONLDProduct {
    let name: String?
    let imageURLString: String?
    let offer: Offer?

    struct Offer {
        let price: Decimal?
        let currency: String?
    }

    init?(html: String) {
        let blocks = HTMLMetadataParser.allMatches(
            in: html,
            pattern: "<script\\b[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        )

        var product: [String: Any]?
        for block in blocks {
            guard let inner = HTMLMetadataParser.firstGroup(
                in: block,
                pattern: "<script[^>]*>(.*?)</script>"
            ) else { continue }

            let cleaned = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }

            if let found = Self.findProduct(in: json) {
                product = found
                break
            }
        }

        guard let product else { return nil }

        self.name = (product["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.imageURLString = Self.firstImage(product["image"])
        self.offer = Self.parseOffer(product["offers"])

        // A node with nothing useful is no better than no node.
        if name == nil, imageURLString == nil, offer == nil { return nil }
    }

    // MARK: - Recursive search

    private static func findProduct(in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if isProduct(dict["@type"]) { return dict }
            if let graph = dict["@graph"], let found = findProduct(in: graph) { return found }
            // Some feeds nest the product under "mainEntity".
            if let main = dict["mainEntity"], let found = findProduct(in: main) { return found }
        }
        if let array = json as? [Any] {
            for element in array {
                if let found = findProduct(in: element) { return found }
            }
        }
        return nil
    }

    private static func isProduct(_ type: Any?) -> Bool {
        if let string = type as? String {
            return string.localizedCaseInsensitiveContains("product")
        }
        if let array = type as? [String] {
            return array.contains { $0.localizedCaseInsensitiveContains("product") }
        }
        return false
    }

    // MARK: - Field extraction

    /// `image` can be a string, an array of strings, an ImageObject, or an
    /// array of those. Return the first usable URL.
    private static func firstImage(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let dict as [String: Any]:
            return dict["url"] as? String ?? dict["contentUrl"] as? String
        case let array as [Any]:
            return array.lazy.compactMap { firstImage($0) }.first
        default:
            return nil
        }
    }

    /// `offers` may be a single Offer, an array, or an AggregateOffer with
    /// low/high prices. Pull a representative price + currency.
    private static func parseOffer(_ value: Any?) -> Offer? {
        let dict: [String: Any]?
        switch value {
        case let single as [String: Any]:
            dict = single
        case let array as [Any]:
            dict = array.compactMap { $0 as? [String: Any] }.first
        default:
            dict = nil
        }
        guard let dict else { return nil }

        let price = decimal(dict["price"])
            ?? decimal(dict["lowPrice"])
            ?? decimal((dict["priceSpecification"] as? [String: Any])?["price"])
        let currency = (dict["priceCurrency"] as? String)
            ?? ((dict["priceSpecification"] as? [String: Any])?["priceCurrency"] as? String)

        guard price != nil || currency != nil else { return nil }
        return Offer(price: price, currency: currency?.uppercased())
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        switch value {
        case let number as NSNumber:
            return Decimal(string: number.stringValue)
        case let string as String:
            return HTMLMetadataParser.decimal(from: string)
        default:
            return nil
        }
    }
}
