import SwiftUI
import UIKit

/// Loads a cached product image off the main thread and fades it in. Keyed on
/// the relative path so it reloads if the cached file is replaced (e.g. after a
/// manual image edit). Shared by the home cards and the detail hero.
struct CachedHeroImage: View {
    let relativePath: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .clipped()
        .task(id: relativePath) {
            let loaded = await Self.load(relativePath)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }

    private static func load(_ relativePath: String) async -> UIImage? {
        let url = ImageCache.fileURL(for: relativePath)
        return await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: url.path)
        }.value
    }
}
