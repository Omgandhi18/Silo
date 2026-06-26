import PhotosUI
import SwiftData
import SwiftUI

/// Manual backstop for when enrichment failed, mis-picked, or never ran. Edited
/// title/source/image are sticky — the coordinator only ever fills blanks, so it
/// won't stomp anything set here. A manual price becomes the saved baseline while
/// re-checks keep showing a live "now" beside it.
struct ItemEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppConstants.defaultCurrencyKey)
    private var defaultCurrency = Locale.current.currency?.identifier ?? "USD"

    @Bindable var item: Item

    @State private var title: String
    @State private var source: String
    @State private var priceText: String
    @State private var currency: String
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isProcessingImage = false

    init(item: Item) {
        self.item = item
        _title = State(initialValue: item.title ?? "")
        _source = State(initialValue: item.sourceDomain ?? "")
        _priceText = State(initialValue: item.savedPrice.map { "\($0)" } ?? "")
        _currency = State(initialValue: item.currencyCode ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.siloCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        imageRow
                        field("Title", text: $title, prompt: "Product name")
                        field("Source", text: $source, prompt: "store.com")
                        priceRow
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .tint(.siloInk)
        }
        .onChange(of: pickedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await replaceImage(with: newValue) }
        }
    }

    // MARK: - Pieces

    private var imageRow: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.siloCardSurface)
                if let path = item.imageLocalPath {
                    CachedHeroImage(relativePath: path)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.siloMutedText)
                }
                if isProcessingImage {
                    ProgressView()
                }
            }
            .frame(width: 84, height: 84)
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Hero image").font(.subheadline).fontWeight(.medium).foregroundStyle(.siloInk)
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(item.imageLocalPath == nil ? "Choose photo" : "Replace photo")
                        .font(.subheadline)
                        .foregroundStyle(.siloClay)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
            TextField(prompt, text: text)
                .font(.body)
                .foregroundStyle(.siloInk)
                .padding(12)
                .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
        }
    }

    private var priceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Price").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
                TextField("0", text: $priceText)
                    .keyboardType(.decimalPad)
                    .font(.body)
                    .foregroundStyle(.siloInk)
                    .padding(12)
                    .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Currency").font(.caption).fontWeight(.medium).foregroundStyle(.siloSecondaryText)
                TextField(defaultCurrency, text: $currency)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body)
                    .foregroundStyle(.siloInk)
                    .frame(width: 88)
                    .padding(12)
                    .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1) }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        item.title = title.trimmedNonEmpty
        item.sourceDomain = source.trimmedNonEmpty

        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        item.currencyCode = trimmedCurrency.isEmpty ? nil : trimmedCurrency

        if let price = HTMLMetadataParser.decimal(from: priceText) {
            // Manual price is the new "when you saved" baseline.
            item.savedPrice = price
            if item.currentPrice == nil { item.currentPrice = price }
        } else if priceText.trimmedNonEmpty == nil {
            item.savedPrice = nil
        }

        // Manual enrichment counts as enriched — don't let it shimmer as "caught".
        if item.state == .caught { item.state = .enriched }

        try? modelContext.save()
        dismiss()
    }

    private func replaceImage(with photo: PhotosPickerItem) async {
        isProcessingImage = true
        defer { isProcessingImage = false }

        guard let data = try? await photo.loadTransferable(type: Data.self) else { return }
        let oldPath = item.imageLocalPath
        guard let newPath = await ImageCache.shared.store(imageData: data, forItemID: item.id) else { return }

        item.imageLocalPath = newPath
        if let oldPath, oldPath != newPath { ImageCache.remove(oldPath) }
        try? modelContext.save()
    }
}
