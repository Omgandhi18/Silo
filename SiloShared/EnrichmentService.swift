import Foundation

nonisolated enum EnrichmentConfig {
    /// Many stores serve a stripped or bot-blocked page to non-browser agents.
    /// A modern Safari UA gets us the real, metadata-rich HTML.
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Don't read more than this much HTML — product metadata lives in the
    /// `<head>`, and some pages stream megabytes of script/markup we never need.
    static let maxBytes = 2_000_000
}

/// The fetch-and-parse pipeline for a single URL. Deliberately free of any
/// SwiftData / main-actor coupling: it takes a URL string and hands back a
/// `Sendable` `ProductMetadata`. The coordinator owns everything stateful.
nonisolated enum EnrichmentService {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": EnrichmentConfig.userAgent]
        return URLSession(configuration: config)
    }()

    static func fetchMetadata(for urlString: String) async -> ProductMetadata? {
        guard let url = normalizedURL(from: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

            // URLSession follows redirects by default; `response.url` is where we
            // actually landed — the right base for canonicalization.
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            let finalURL = http.url ?? url

            // If it isn't HTML (e.g. a direct image/PDF link), there's nothing to
            // parse — but still hand back a canonicalized URL + domain so the item
            // gets a sensible identity and stops looking "unenriched".
            let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            guard contentType.isEmpty || contentType.contains("html") else {
                return ProductMetadata(
                    sourceDomain: finalURL.host(),
                    resolvedURLString: finalURL.absoluteString,
                    canonicalURLString: URLCanonicalizer.canonicalize(finalURL)
                )
            }

            let clipped = data.prefix(EnrichmentConfig.maxBytes)
            guard let html = decodeHTML(Data(clipped), response: http) else { return nil }

            return HTMLMetadataParser(html: html, baseURL: finalURL).parse()
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    /// Tolerate URLs that arrive without a scheme ("shop.com/x").
    private static func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }

    /// Decode bytes using the charset the server declared, falling back to UTF-8
    /// then Latin-1 (which never fails, so we always get *something*).
    private static func decodeHTML(_ data: Data, response: HTTPURLResponse) -> String? {
        if let name = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                if let string = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)) {
                    return string
                }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
