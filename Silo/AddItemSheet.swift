import PhotosUI
import SwiftData
import SwiftUI
import UIKit

/// In-app counterpart to the Share Extension. Drop in just a link and let
/// enrichment do the rest, or fill in everything by hand for something that has
/// no good page (a shop find, a gift idea). A link still drives auto-enrichment;
/// anything you type is treated as authored and won't be overwritten.
struct AddItemSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SiloCollection.createdAt) private var collections: [SiloCollection]

    @AppStorage(AppConstants.defaultCurrencyKey)
    private var defaultCurrency = Locale.current.currency?.identifier ?? "USD"

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

    /// Tolerates a bare "store.com/x" by assuming https; requires a real host so
    /// we don't file gibberish. Nil when the field is empty — a URL is optional.
    private var normalizedURL: URL? {
        guard let trimmed = urlText.trimmedNonEmpty else { return nil }
        let candidate = (URL(string: trimmed)?.scheme != nil)
            ? URL(string: trimmed)
            : URL(string: "https://\(trimmed)")
        guard let url = candidate, let host = url.host(), host.contains(".") else { return nil }
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
                        Text("Paste a link and Silo fills in the rest — or enter the details yourself.")
                            .font(.subheadline)
                            .foregroundStyle(.siloSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        urlField
                        imageRow
                        field("Title", text: $title, prompt: "Product name")
                        field("Source", text: $source, prompt: "store.com")
                        priceRow
                        collectionRow
                        noteField
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
                        .disabled(!canSave)
                }
            }
            .tint(.siloInk)
        }
        .presentationDragIndicator(.visible)
        .onAppear { urlFocused = true }
        .onChange(of: pickedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await loadPreview(newValue) }
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
            .padding(12)
            .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.sentences)
                .font(.body)
                .foregroundStyle(.siloInk)
                .padding(12)
                .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
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
                    .padding(12)
                    .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Currency").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
                TextField(defaultCurrency, text: $currency)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body).foregroundStyle(.siloInk)
                    .frame(width: 88)
                    .padding(12)
                    .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
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
                .padding(12)
                .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            TextField("Why you saved it, a size, a reminder…", text: $note, axis: .vertical)
                .font(.body).foregroundStyle(.siloInk)
                .lineLimit(2...5)
                .padding(12)
                .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
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
        guard canSave else { return }

        let urlString = normalizedURL?.absoluteString ?? ""

        // Soft-dedupe against the active shelf, same as the extension.
        if let existing = activeDuplicate(of: urlString) {
            existing.savedAt = Date()
            try? modelContext.save()
            Haptics.tap()
            dismiss()
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
        Haptics.tap()
        dismiss()
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
