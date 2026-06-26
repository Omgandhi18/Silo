import Foundation
import SwiftData

/// Drives enrichment for the app: finds freshly-caught items, fetches their
/// metadata off the main actor with a bounded number of concurrent requests,
/// then writes results back onto the models and resolves duplicates.
///
/// Lives entirely in the app target — the Share Extension stays dumb and fast,
/// only ever writing a `.caught` stub. All the networking happens here, where
/// we have the time and memory budget for it.
@MainActor
@Observable
final class EnrichmentCoordinator {
    private let context: ModelContext

    /// Items currently being worked on, so overlapping sweeps don't double-fetch.
    private var inFlight: Set<UUID> = []
    private var isSweeping = false

    /// How many pages we'll fetch at once. Stores are slow and we're polite.
    private let maxConcurrent = 4

    init(context: ModelContext) {
        self.context = context
    }

    /// Enrich every item still in the `.caught` state. Safe to call repeatedly
    /// (on launch, on foreground); concurrent calls coalesce.
    func sweep() async {
        guard !isSweeping else { return }
        isSweeping = true
        defer { isSweeping = false }

        let pending = pendingItems()
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: EnrichmentResult?.self) { group in
            var next = 0

            func scheduleNext() {
                guard next < pending.count else { return }
                let job = pending[next]
                next += 1
                group.addTask {
                    await Self.process(id: job.id, urlString: job.urlString)
                }
            }

            for _ in 0..<min(maxConcurrent, pending.count) { scheduleNext() }

            for await result in group {
                if let result { apply(result) }
                scheduleNext()
            }
        }
    }

    // MARK: - Gathering work

    private struct Job: Sendable {
        let id: UUID
        let urlString: String
    }

    private func pendingItems() -> [Job] {
        let caughtRaw = ItemState.caught.rawValue
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.stateRaw == caughtRaw }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        return items.compactMap { item in
            guard !inFlight.contains(item.id), !item.urlString.isEmpty else { return nil }
            inFlight.insert(item.id)
            return Job(id: item.id, urlString: item.urlString)
        }
    }

    // MARK: - Off-main work

    nonisolated private struct EnrichmentResult: Sendable {
        let id: UUID
        let metadata: ProductMetadata
        let imageRelativePath: String?
    }

    nonisolated private static func process(id: UUID, urlString: String) async -> EnrichmentResult? {
        guard let metadata = await EnrichmentService.fetchMetadata(for: urlString) else {
            return nil
        }
        var imagePath: String?
        if let imageURL = metadata.imageURL {
            imagePath = await ImageCache.shared.store(imageURL, forItemID: id)
        }
        return EnrichmentResult(id: id, metadata: metadata, imageRelativePath: imagePath)
    }

    // MARK: - Applying results

    private func apply(_ result: EnrichmentResult) {
        defer { inFlight.remove(result.id) }

        guard let item = item(with: result.id) else { return }
        let m = result.metadata

        // Don't clobber anything the user (or a richer earlier pass) already set —
        // only fill blanks. Title/price/image flow in; state always advances.
        if let title = m.title, isBlank(item.title) {
            item.title = title
        }
        if let domain = m.sourceDomain, isBlank(item.sourceDomain) {
            item.sourceDomain = domain
        }
        if let path = result.imageRelativePath, isBlank(item.imageLocalPath) {
            item.imageLocalPath = path
        }
        if let price = m.price {
            // First price we ever see becomes the "saved" baseline for then-vs-now.
            if item.savedPrice == nil { item.savedPrice = price }
            item.currentPrice = price
            item.priceCheckedAt = Date()
        }
        if let currency = m.currencyCode, isBlank(item.currencyCode) {
            item.currencyCode = currency
        }
        if let canonical = m.canonicalURLString {
            item.canonicalURLString = canonical
        }
        if let resolved = m.resolvedURLString {
            item.urlString = resolved
        }

        item.state = .enriched

        resolveDuplicates(of: item)
        try? context.save()
    }

    /// If two active items share a canonical URL (e.g. the same product shared
    /// from Safari and from a store app), keep the oldest, fold in anything the
    /// survivor is missing, and drop the rest.
    private func resolveDuplicates(of item: Item) {
        guard let canonical = item.canonicalURLString, !canonical.isEmpty else { return }

        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.canonicalURLString == canonical }
        )
        let matches = ((try? context.fetch(descriptor)) ?? []).filter {
            $0.state == .caught || $0.state == .enriched
        }
        guard matches.count > 1 else { return }

        let survivor = matches.min { $0.savedAt < $1.savedAt } ?? item
        for duplicate in matches where duplicate.id != survivor.id {
            merge(duplicate, into: survivor)
            if let path = duplicate.imageLocalPath, path != survivor.imageLocalPath {
                ImageCache.remove(path)
            }
            inFlight.remove(duplicate.id)
            context.delete(duplicate)
        }
    }

    private func merge(_ source: Item, into target: Item) {
        if isBlank(target.title) { target.title = source.title }
        if isBlank(target.imageLocalPath) { target.imageLocalPath = source.imageLocalPath }
        if isBlank(target.sourceDomain) { target.sourceDomain = source.sourceDomain }
        if isBlank(target.note) { target.note = source.note }
        if isBlank(target.currencyCode) { target.currencyCode = source.currencyCode }
        if target.savedPrice == nil { target.savedPrice = source.savedPrice }
        if target.currentPrice == nil { target.currentPrice = source.currentPrice }
        // Prefer a user-assigned collection over none.
        if target.collection == nil { target.collection = source.collection }
    }

    private func item(with id: UUID) -> Item? {
        let descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}
