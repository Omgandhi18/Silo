import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private var providers: [NSItemProvider] = []
    private var didComplete = false

    // The confirmation is now the shared SwiftUI "magic" card, hosted here.
    private let model = SavedSheetModel()
    private var context: ModelContext?
    private var savedItem: Item?
    private var enrichTask: Task<Void, Never>?

    private let canvas = UIColor { traits in
        UIColor(siloHex: traits.userInterfaceStyle == .dark ? "#1C1916" : "#F4EEE4")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = canvas
        captureFirstLink()
    }

    // MARK: - Link capture

    private func captureFirstLink() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("No link found")
            return
        }
        providers = extensionItems.flatMap { $0.attachments ?? [] }
        loadURL(index: 0)
    }

    private func loadURL(index: Int) {
        guard index < providers.count else {
            showError("No link found")
            return
        }

        let provider = providers[index]

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                let resolvedURL = Self.url(from: item)
                Task { @MainActor in
                    guard let self else { return }
                    if let url = resolvedURL { self.save(url) } else { self.loadURL(index: index + 1) }
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                let resolvedURL = Self.text(from: item).flatMap(Self.firstURL(in:))
                Task { @MainActor in
                    guard let self else { return }
                    if let url = resolvedURL { self.save(url) } else { self.loadURL(index: index + 1) }
                }
            }
            return
        }

        loadURL(index: index + 1)
    }

    // MARK: - Save + enrich

    private func save(_ url: URL) {
        let container = PersistenceController.makeContainer()
        let context = ModelContext(container)
        self.context = context
        let urlString = url.absoluteString

        let item: Item
        if let existing = try? context.fetch(Self.activeDescriptor(for: urlString)).first {
            existing.savedAt = Date()
            item = existing
        } else {
            let newItem = Item(urlString: urlString, originalURLString: urlString)
            newItem.sourceDomain = url.host()
            newItem.state = .caught
            context.insert(newItem)
            item = newItem
        }
        try? context.save()
        savedItem = item

        let alreadyEnriched = item.state == .enriched
        model.phase = alreadyEnriched ? .done : .enriching
        model.title = item.title
        model.domain = item.sourceDomain ?? url.host()
        model.priceText = item.formattedPrice
        model.imageRelativePath = item.imageLocalPath
        model.collections = Self.chips(from: context)
        model.selectedCollectionID = item.collection?.id

        presentCard()

        if alreadyEnriched {
            Haptics.success()
        } else {
            enrichTask = Task { await enrich(item: item, context: context) }
        }
    }

    /// One inline enrichment pass — the same stateless engine the app's sweep
    /// uses. If it can't reach the page the item just stays `.caught` and the
    /// app finishes the job later.
    private func enrich(item: Item, context: ModelContext) async {
        let urlString = item.urlString

        if !urlString.isEmpty, let m = await EnrichmentService.fetchMetadata(for: urlString) {
            if let title = m.title, isBlank(item.title) { item.title = title }
            if let domain = m.sourceDomain, isBlank(item.sourceDomain) { item.sourceDomain = domain }
            if let currency = m.currencyCode, isBlank(item.currencyCode) { item.currencyCode = currency }
            if let price = m.price {
                if item.savedPrice == nil { item.savedPrice = price }
                item.currentPrice = price
                item.priceCheckedAt = Date()
            }
            if let canonical = m.canonicalURLString { item.canonicalURLString = canonical }
            if let resolved = m.resolvedURLString { item.urlString = resolved }
            if let imageURL = m.imageURL, isBlank(item.imageLocalPath),
               let path = await ImageCache.shared.store(imageURL, forItemID: item.id) {
                item.imageLocalPath = path
            }
            item.state = .enriched
            try? context.save()
        }

        guard !Task.isCancelled else { return }

        model.title = item.title
        model.domain = item.sourceDomain
        model.priceText = item.formattedPrice
        model.imageRelativePath = item.imageLocalPath
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { model.phase = .done }
    }

    // MARK: - Hosting the card

    private func presentCard() {
        let root = SavedProductSheet(
            model: model,
            onSelectCollection: { [weak self] id in self?.fileInto(id) },
            onDone: { [weak self] in self?.finish() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func fileInto(_ id: UUID?) {
        guard let context, let item = savedItem else { return }
        if let id {
            item.collection = try? context.fetch(
                FetchDescriptor<SiloCollection>(predicate: #Predicate { $0.id == id })
            ).first
        } else {
            item.collection = nil
        }
        try? context.save()
    }

    private func finish() {
        guard !didComplete else { return }
        didComplete = true
        enrichTask?.cancel()
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - Error fallback

    private func showError(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = UIColor { traits in
            UIColor(siloHex: traits.userInterfaceStyle == .dark ? "#EDE6D9" : "#2C2823")
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        Haptics.error()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - Helpers

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private static func activeDescriptor(for urlString: String) -> FetchDescriptor<Item> {
        FetchDescriptor<Item>(
            predicate: #Predicate {
                ($0.stateRaw == "caught" || $0.stateRaw == "enriched") && $0.urlString == urlString
            }
        )
    }

    private static func chips(from context: ModelContext) -> [CollectionChip] {
        let descriptor = FetchDescriptor<SiloCollection>(sortBy: [SortDescriptor(\.createdAt)])
        let collections = (try? context.fetch(descriptor)) ?? []
        return collections.map {
            CollectionChip(id: $0.id, name: $0.name, lightHex: $0.colorHex, darkHex: $0.darkColorHex)
        }
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let string = item as? String { return firstURL(in: string) }
        if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return firstURL(in: string)
        }
        return nil
    }

    nonisolated private static func text(from item: NSSecureCoding?) -> String? {
        if let string = item as? String { return string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    nonisolated private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }
}
