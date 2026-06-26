import Foundation
import SwiftData

enum ItemState: String, Codable, CaseIterable {
    case caught
    case enriched
    case gotIt
    case abandoned
}

@Model
final class Item {
    var id: UUID = UUID()

    var urlString: String = ""
    var originalURLString: String?

    // Stable, tracking-stripped form of the URL. Used to spot the same product
    // arriving twice from different share paths (Safari vs. an app's share sheet).
    var canonicalURLString: String?

    var title: String?
    var sourceDomain: String?
    var imageLocalPath: String?
    var faviconLocalPath: String?

    var savedPrice: Decimal?
    var currentPrice: Decimal?
    var currencyCode: String?
    var priceCheckedAt: Date?

    var note: String?
    var savedAt: Date = Date()
    var stateRaw: String = ItemState.caught.rawValue

    var collection: SiloCollection?

    var state: ItemState {
        get { ItemState(rawValue: stateRaw) ?? .caught }
        set { stateRaw = newValue.rawValue }
    }

    var url: URL? {
        URL(string: urlString)
    }

    init(urlString: String, originalURLString: String? = nil) {
        self.urlString = urlString
        self.originalURLString = originalURLString
    }
}

@Model
final class SiloCollection {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = ""
    var darkColorHex: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Item.collection)
    var items: [Item] = []

    init(name: String, colorHex: String, darkColorHex: String) {
        self.name = name
        self.colorHex = colorHex
        self.darkColorHex = darkColorHex
    }
}
