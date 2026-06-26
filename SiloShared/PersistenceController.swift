import Foundation
import SwiftData

enum PersistenceController {
    static let schema = Schema([
        Item.self,
        SiloCollection.self
    ])

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            return inMemoryContainer()
        }

        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL(),
            allowsSave: true
        )

        // First choice: the real, persistent App Group store.
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        // The on-disk store couldn't be opened — most often an incompatible
        // schema left behind by an earlier build during development. Rather than
        // crash-loop on launch, move the old store aside and start clean.
        archiveExistingStore()
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        // Last resort: keep the app usable for this session even if disk is
        // unavailable. Data won't persist, but it won't abort on launch either.
        return inMemoryContainer()
    }

    @MainActor
    private static func inMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        // An in-memory store has no disk to fail against; if this throws the
        // schema itself is malformed, which is a programmer error worth trapping.
        return try! ModelContainer(for: schema, configurations: [configuration])
    }

    /// Renames the existing store (and its -wal/-shm siblings) so SwiftData can
    /// recreate a fresh one. We rename rather than delete so a corrupt store is
    /// still recoverable off-device if needed.
    private static func archiveExistingStore() {
        let store = storeURL()
        let suffix = "-broken-\(Int(Date().timeIntervalSince1970))"
        let fileManager = FileManager.default

        for sibling in ["", "-wal", "-shm"] {
            let url = store.deletingLastPathComponent()
                .appendingPathComponent(store.lastPathComponent + sibling)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            let destination = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + suffix)
            try? fileManager.moveItem(at: url, to: destination)
        }
    }

    nonisolated static func imageCacheDirectoryURL() -> URL {
        let directory = sharedContainerURL()
            .appendingPathComponent(AppConstants.imageCacheDirectoryName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        return directory
    }

    private static func storeURL() -> URL {
        sharedContainerURL()
            .appendingPathComponent(AppConstants.modelStoreFileName)
    }

    nonisolated private static func sharedContainerURL() -> URL {
        if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ) {
            return appGroupURL
        }

        return URL.documentsDirectory
    }
}
