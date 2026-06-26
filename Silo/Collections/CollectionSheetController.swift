import Foundation

/// What the collection sheet is doing right now. `create` optionally carries the
/// id of an item to file into the new collection — that's how "+ New collection"
/// from a card's long-press menu both creates *and* files in one gesture.
enum CollectionSheetMode {
    case create(fileItemID: UUID?)
    case edit(SiloCollection)
}

/// Shared, environment-injected switch for presenting the collection create/edit
/// sheet. Cards, pills, and the toolbar all sit at different depths of the view
/// tree; rather than thread bindings through every layer, they reach for this
/// from the environment and flip it. `HomeView` owns the actual sheet.
@MainActor
@Observable
final class CollectionSheetController {
    var mode: CollectionSheetMode?

    var isPresented: Bool {
        get { mode != nil }
        set { if !newValue { mode = nil } }
    }

    func createNew(filing itemID: UUID? = nil) {
        mode = .create(fileItemID: itemID)
    }

    func edit(_ collection: SiloCollection) {
        mode = .edit(collection)
    }
}
