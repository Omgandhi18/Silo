import SwiftData
import UIKit
import UniformTypeIdentifiers

@MainActor
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private var didComplete = false
    private var providers: [NSItemProvider] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        captureFirstLink()
    }

    private func configureView() {
        view.backgroundColor = UIColor(red: 0.957, green: 0.933, blue: 0.894, alpha: 1)

        statusLabel.text = "Saving to \(AppConstants.displayName)..."
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textColor = UIColor(red: 0.173, green: 0.157, blue: 0.137, alpha: 1)
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func captureFirstLink() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish(message: "No link found")
            return
        }

        providers = extensionItems.flatMap { $0.attachments ?? [] }
        loadURL(index: 0)
    }

    private func loadURL(index: Int) {
        guard index < providers.count else {
            finish(message: "No link found")
            return
        }

        let provider = providers[index]

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                let resolvedURL = Self.url(from: item)

                Task { @MainActor in
                    guard let self else { return }

                    if let url = resolvedURL {
                        self.save(url)
                    } else {
                        self.loadURL(index: index + 1)
                    }
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                let resolvedURL = Self.text(from: item).flatMap(Self.firstURL(in:))

                Task { @MainActor in
                    guard let self else { return }

                    if let url = resolvedURL {
                        self.save(url)
                    } else {
                        self.loadURL(index: index + 1)
                    }
                }
            }
            return
        }

        loadURL(index: index + 1)
    }

    private func save(_ url: URL) {
        let container = PersistenceController.makeContainer()
        let context = ModelContext(container)
        let urlString = url.absoluteString

        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate {
                ($0.stateRaw == "caught" || $0.stateRaw == "enriched") && $0.urlString == urlString
            }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.savedAt = Date()
        } else {
            let item = Item(urlString: urlString, originalURLString: urlString)
            item.sourceDomain = url.host()
            item.state = .caught
            context.insert(item)
        }

        do {
            try context.save()
            finish(message: "Saved to \(AppConstants.displayName)")
        } catch {
            finish(message: "Could not save link")
        }
    }

    private func finish(message: String) {
        guard !didComplete else { return }
        didComplete = true

        statusLabel.text = message

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let string = item as? String {
            return firstURL(in: string)
        }

        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return firstURL(in: string)
        }

        return nil
    }

    nonisolated private static func text(from item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return string
        }

        if let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    nonisolated private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return detector?
            .firstMatch(in: text, options: [], range: range)?
            .url
    }
}
