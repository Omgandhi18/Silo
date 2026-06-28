import UIKit

/// Downloads and stores product hero images in the shared App Group container,
/// so both the app and (future) widgets/extensions can read them, and so they
/// survive app relaunches without re-fetching.
///
/// An actor because writes to the cache directory and the in-flight bookkeeping
/// shouldn't race. The heavy lifting (network, disk) is all `async`.
actor ImageCache {
    static let shared = ImageCache()

    /// Cap the longest edge — store pages happily serve 4000px hero shots and we
    /// only ever render a card. Keeps the App Group container from ballooning.
    private let maxDimension: CGFloat = 1200

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
    }

    /// Downloads `url`, downscales it, writes it into the App Group, and returns
    /// the *relative* filename to persist on the item. Relative on purpose — the
    /// App Group container path isn't stable across installs.
    func store(_ url: URL, forItemID id: UUID) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.setValue(EnrichmentConfig.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            return try write(image, forItemID: id)
        } catch {
            return nil
        }
    }

    /// Stores image bytes the user picked manually (e.g. via PhotosPicker),
    /// replacing any existing cached hero. Returns the new relative filename.
    func store(imageData data: Data, forItemID id: UUID) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return try? write(image, forItemID: id)
    }

    /// Downscale, JPEG-encode, and atomically write. A fresh filename each time
    /// (uuid + timestamp) so the UI, which keys on the path, reliably reloads
    /// after a replacement instead of showing a stale cached decode.
    private func write(_ image: UIImage, forItemID id: UUID) throws -> String {
        let resized = downscaled(image)
        guard let encoded = resized.jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let filename = "\(id.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
        let fileURL = PersistenceController.imageCacheDirectoryURL()
            .appendingPathComponent(filename)
        try encoded.write(to: fileURL, options: .atomic)
        return filename
    }

    /// Removes a cached image (used when an item is deleted).
    nonisolated static func remove(_ relativePath: String) {
        let fileURL = PersistenceController.imageCacheDirectoryURL()
            .appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Absolute URL for a stored image, for the UI to load.
    nonisolated static func fileURL(for relativePath: String) -> URL {
        PersistenceController.imageCacheDirectoryURL()
            .appendingPathComponent(relativePath)
    }

    private func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
