import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// In-app counterpart to the Share Extension. Drop in just a link and let
/// enrichment do the rest, or fill in everything by hand for something that has
/// no good page (a shop find, a gift idea). A link still drives auto-enrichment;
/// anything you type is treated as authored and won't be overwritten.
///
/// The sheet opens on the fast path — a single link field — and only unfolds the
/// full form when you choose to enter the details yourself.
struct AddItemSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SiloCollection.createdAt) private var collections: [SiloCollection]

    @AppStorage(AppConstants.defaultCurrencyKey)
    private var defaultCurrency = Locale.current.currency?.identifier ?? "USD"

    /// Which way the user is filing this — paste a link, or type it all out.
    private enum Mode { case link, manual }
    @State private var mode: Mode = .link

    @State private var urlText = ""
    @State private var title = ""
    @State private var source = ""
    @State private var priceText = ""
    @State private var currency = ""
    @State private var note = ""
    @State private var selectedCollection: SiloCollection?

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var pickedImageData: Data?
    @State private var previewImage: UIImage?
    @State private var isProcessingImage = false

    @FocusState private var urlFocused: Bool
    @FocusState private var titleFocused: Bool

    @State private var savedModel: SavedSheetModel?
    @State private var savedItem: Item?

    /// Finds the link to file. Pasted text is often messy — stores like Amazon
    /// share "Title … https://…" — so we first let `NSDataDetector` pull a real
    /// link out of anywhere in the string. Failing that, we tolerate a bare
    /// "store.com/x" by assuming https. Nil when there's nothing link-shaped.
    private var normalizedURL: URL? {
        guard let trimmed = urlText.trimmedNonEmpty else { return nil }

        if let detected = Self.firstURL(in: trimmed) { return detected }

        let candidate = (URL(string: trimmed)?.scheme != nil)
            ? URL(string: trimmed)
            : URL(string: "https://\(trimmed)")
        guard let url = candidate, let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    /// First http(s) link anywhere in `text`, via the system data detector.
    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let url = detector?.firstMatch(in: text, options: [], range: range)?.url,
              let scheme = url.scheme, scheme.hasPrefix("http") else { return nil }
        return url
    }

    /// Need at least *something* to file: a link or a title.
    private var canSave: Bool {
        normalizedURL != nil || title.trimmedNonEmpty != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.siloCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch mode {
                        case .link:   linkStep
                        case .manual: manualStep
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave || savedModel != nil)
                }
            }
            .tint(.siloInk)
        }
        .overlay { savedOverlay }
        .presentationDragIndicator(.visible)
        .onAppear { urlFocused = true }
        .onChange(of: pickedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await loadPreview(newValue) }
        }
        .onChange(of: mode) { _, newMode in
            // Hand focus to the field that just became the centre of attention.
            switch newMode {
            case .link:   urlFocused = true
            case .manual: titleFocused = true
            }
        }
    }

    // MARK: - Steps

    /// Step one: just a link, plus the door into the manual form.
    private var linkStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Paste a link and Silo fills in the rest.")
                .font(.subheadline)
                .foregroundStyle(.siloSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            urlField

            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.25)) { mode = .manual }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil").font(.caption)
                    Text("or enter the details yourself")
                }
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(.siloClay)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
    }

    /// Step two: the full form, for finds that have no good page to read.
    private var manualStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.25)) { mode = .link }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.caption.weight(.semibold))
                    Text("Have a link? Paste it instead")
                }
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(.siloClay)
            }
            .buttonStyle(.plain)

            imageRow
            titleField
            field("Source", text: $source, prompt: "store.com")
            priceRow
            collectionRow
            noteField
        }
        .transition(.opacity)
    }

    // MARK: - Confirmation

    /// The shared "magic" card — the in-app twin of the Share Extension's
    /// confirmation, so filing feels the same wherever you do it.
    @ViewBuilder
    private var savedOverlay: some View {
        if let savedModel {
            SavedProductSheet(
                model: savedModel,
                onSelectCollection: { id in
                    savedItem?.collection = collections.first { $0.id == id }
                    try? modelContext.save()
                },
                onDone: { dismiss() }
            )
            .transition(.opacity)
        }
    }

    // MARK: - Fields

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            HStack(spacing: 10) {
                TextField("https://…", text: $urlText)
                    .focused($urlFocused)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .foregroundStyle(.siloInk)

                if UIPasteboard.general.hasStrings {
                    Button("Paste") {
                        if let pasted = UIPasteboard.general.string {
                            urlText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .font(.subheadline).fontWeight(.medium)
                    .buttonStyle(.plain)
                    .foregroundStyle(.siloClay)
                }
            }
            .siloFieldBox()
        }
    }

    /// Title gets its own view (not the shared `field` helper) so we can focus it
    /// the moment the manual form appears.
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            TextField("Product name", text: $title)
                .focused($titleFocused)
                .textInputAutocapitalization(.sentences)
                .font(.body)
                .foregroundStyle(.siloInk)
                .siloFieldBox()
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.sentences)
                .font(.body)
                .foregroundStyle(.siloInk)
                .siloFieldBox()
        }
    }

    private var imageRow: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.siloCardSurface)
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo").foregroundStyle(.siloMutedText)
                }
                if isProcessingImage { ProgressView() }
            }
            .frame(width: 84, height: 84)
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 6) {
                Text("Image").font(.subheadline).fontWeight(.medium).foregroundStyle(.siloInk)
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(previewImage == nil ? "Choose photo" : "Replace photo")
                        .font(.subheadline).foregroundStyle(.siloClay)
                }
                Text("Optional — a link fetches one automatically.")
                    .font(.caption).foregroundStyle(.siloMutedText)
            }
            Spacer(minLength: 0)
        }
    }

    private var priceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Price").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
                TextField("0", text: $priceText)
                    .keyboardType(.decimalPad)
                    .font(.body).foregroundStyle(.siloInk)
                    .siloFieldBox()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Currency").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
                TextField(defaultCurrency, text: $currency)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body).foregroundStyle(.siloInk)
                    .frame(width: 88)
                    .siloFieldBox()
            }
        }
    }

    private var collectionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collection").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            Menu {
                Button("Unsorted") { selectedCollection = nil }
                ForEach(collections) { collection in
                    Button(collection.name) { selectedCollection = collection }
                }
            } label: {
                HStack(spacing: 8) {
                    if let color = selectedCollection?.displayColor(for: colorScheme) {
                        Circle().fill(color).frame(width: 8, height: 8)
                    }
                    Text(selectedCollection?.name ?? "Unsorted")
                        .foregroundStyle(.siloInk)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption).foregroundStyle(.siloMutedText)
                }
                .siloFieldBox()
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            TextField("Why you saved it, a size, a reminder…", text: $note, axis: .vertical)
                .font(.body).foregroundStyle(.siloInk)
                .lineLimit(2...5)
                .siloFieldBox()
        }
    }

    // MARK: - Actions

    private func loadPreview(_ photo: PhotosPickerItem) async {
        isProcessingImage = true
        defer { isProcessingImage = false }
        guard let data = try? await photo.loadTransferable(type: Data.self) else { return }
        pickedImageData = data
        previewImage = UIImage(data: data)
    }

    private func add() async {
        guard canSave, savedModel == nil else { return }

        let urlString = normalizedURL?.absoluteString ?? ""

        // Soft-dedupe against the active shelf, same as the extension.
        if let existing = activeDuplicate(of: urlString) {
            existing.savedAt = Date()
            try? modelContext.save()
            presentSaved(item: existing, enrich: false)
            return
        }

        let item = Item(urlString: urlString,
                        originalURLString: urlString.isEmpty ? nil : urlString)

        item.title = title.trimmedNonEmpty
        item.sourceDomain = source.trimmedNonEmpty ?? normalizedURL?.host()
        item.note = note.trimmedNonEmpty

        let typedCurrency = currency.trimmedNonEmpty?.uppercased()

        if let price = HTMLMetadataParser.decimal(from: priceText) {
            item.savedPrice = price
            item.currentPrice = price
            // A manual price needs a currency to read right — use the typed one,
            // else fall back to the default from Settings.
            item.currencyCode = typedCurrency ?? defaultCurrency
        } else if let typedCurrency {
            // No price, but they named a currency — keep it. Otherwise leave nil
            // so enrichment can read the page's own currency.
            item.currencyCode = typedCurrency
        }

        item.collection = selectedCollection

        // With a link we leave it `.caught` so the sweep fills any blanks (manual
        // fields are sticky — the coordinator only ever fills empties). Without a
        // link there's nothing to fetch, so it's already `.enriched`.
        item.state = normalizedURL != nil ? .caught : .enriched

        modelContext.insert(item)

        if let data = pickedImageData,
           let path = await ImageCache.shared.store(imageData: data, forItemID: item.id) {
            item.imageLocalPath = path
        }

        try? modelContext.save()
        presentSaved(item: item, enrich: normalizedURL != nil)
    }

    /// Swaps the form for the shared "magic" card. With a link, we kick off a
    /// live enrichment pass and let the card sparkle into shape; without one,
    /// the card is already complete from what was typed.
    private func presentSaved(item: Item, enrich: Bool) {
        savedItem = item
        let model = SavedSheetModel(
            phase: enrich ? .enriching : .done,
            title: item.title,
            domain: item.sourceDomain,
            priceText: item.formattedPrice,
            imageRelativePath: item.imageLocalPath,
            collections: collections.map {
                CollectionChip(id: $0.id, name: $0.name, lightHex: $0.colorHex, darkHex: $0.darkColorHex)
            },
            selectedCollectionID: item.collection?.id
        )

        withAnimation(.easeInOut(duration: 0.3)) { savedModel = model }

        if enrich {
            Task { await enrichAndFill(item: item, model: model) }
        } else {
            Haptics.success()
        }
    }

    /// Runs a single enrichment pass inline (the same engine the background sweep
    /// uses), fills any blanks, and feeds the results into the card. Failure is
    /// soft: the item stays `.caught` for the app's sweep to finish later.
    private func enrichAndFill(item: Item, model: SavedSheetModel) async {
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
            try? modelContext.save()
        }

        model.title = item.title
        model.domain = item.sourceDomain
        model.priceText = item.formattedPrice
        model.imageRelativePath = item.imageLocalPath
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { model.phase = .done }
    }

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private func activeDuplicate(of urlString: String) -> Item? {
        guard !urlString.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate {
                ($0.stateRaw == "caught" || $0.stateRaw == "enriched") && $0.urlString == urlString
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

private extension View {
    /// The shared rounded card-surface treatment worn by every input box.
    func siloFieldBox() -> some View {
        self
            .padding(12)
            .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
    }
}
