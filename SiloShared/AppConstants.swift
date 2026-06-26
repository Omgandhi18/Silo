import Foundation

nonisolated enum AppConstants {
    static let displayName = "Silo"
    static let tagline = "Your product stash."
    static let appGroupIdentifier = "group.OmGandhi.Silo"
    static let imageCacheDirectoryName = "Images"
    static let modelStoreFileName = "Silo.store"

    /// UserDefaults key for the user's preferred currency (set in Settings, used
    /// as the fallback when an item carries no currency of its own).
    static let defaultCurrencyKey = "defaultCurrencyCode"
}
