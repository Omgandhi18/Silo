import SwiftData
import SwiftUI

/// The product's home inside Silo: hero, price story, a place for a note, and the
/// one clay "Open & Buy" button that sends you back out to the retailer.
struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CollectionSheetController.self) private var collectionSheet

    @Query(sort: \SiloCollection.createdAt) private var collections: [SiloCollection]

    @Bindable var item: Item

    @State private var isRechecking = false
    @State private var showEdit = false

    private var noteBinding: Binding<String> {
        Binding(
            get: { item.note ?? "" },
            set: { item.note = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                titleBlock
                priceBlock
                if showsDecayPrompt { decayPrompt }
                noteBlock
                metaBlock
            }
            .padding(20)
            .padding(.bottom, 12)
        }
        .background(Color.siloCanvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { buyBar }
        .toolbar { toolbarContent }
        .tint(.siloInk)
        .refreshable { await recheckPrice(force: true) }
        .task { await recheckPrice(force: false) }
        .sheet(isPresented: $showEdit) {
            ItemEditSheet(item: item)
        }
        .onDisappear { try? modelContext.save() }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.siloCardBorder.opacity(0.7),
                            Color.siloCanvas.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let path = item.imageLocalPath {
                CachedHeroImage(relativePath: path)
            } else {
                Image(systemName: item.state == .caught ? "sparkles" : "shippingbox")
                    .font(.largeTitle)
                    .foregroundStyle(.siloMutedText)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).stroke(.siloCardBorder, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if let color = item.collection?.displayColor(for: colorScheme) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(item.collection?.name ?? "")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.siloInk)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.siloCardSurface, in: Capsule())
                .padding(12)
            }
        }
    }

    // MARK: - Title / source

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title ?? item.url?.host() ?? "Saved link")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.siloInk)
                .fixedSize(horizontal: false, vertical: true)

            if let source = item.sourceDomain {
                Text(source)
                    .font(.subheadline)
                    .foregroundStyle(.siloSecondaryText)
            }
        }
    }

    // MARK: - Price (then vs now)

    @ViewBuilder
    private var priceBlock: some View {
        if let saved = item.savedPrice,
           let now = item.currentPrice,
           item.priceCheckedAt != nil,
           saved != now,
           let savedText = PriceFormatter.string(saved, currencyCode: item.currencyCode),
           let nowText = PriceFormatter.string(now, currencyCode: item.currencyCode) {
            // We have a real before/after to tell.
            let dropped = now < saved
            HStack(spacing: 8) {
                Text(savedText)
                    .strikethrough()
                    .foregroundStyle(.siloStruckPrice)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.siloMutedText)
                Text(nowText)
                    .fontWeight(.semibold)
                    .foregroundStyle(dropped ? Color(hex: "#5A9488") : .siloInk)
                if dropped {
                    Image(systemName: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#5A9488"))
                }
            }
            .font(.title3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(savedText) when you saved, now \(nowText)"
                + (dropped ? ", price dropped" : ", price went up")
            )
        } else if let single = PriceFormatter.string(item.currentPrice ?? item.savedPrice, currencyCode: item.currencyCode) {
            Text(single)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.siloInk)
        }
    }

    // MARK: - Note

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.siloSecondaryText)

            TextField("Why you saved it, a size, a reminder…", text: noteBinding, axis: .vertical)
                .font(.body)
                .foregroundStyle(.siloInk)
                .lineLimit(2...6)
                .padding(12)
                .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1)
                }
        }
    }

    // MARK: - Meta

    private var metaBlock: some View {
        Text("Saved \(item.savedAt.formatted(.relative(presentation: .named)))")
            .font(.caption)
            .foregroundStyle(.siloMutedText)
    }

    // MARK: - Intent decay (P1)

    /// Roughly four months. We never notify — this only ever speaks when the user
    /// is already looking at the item.
    private var showsDecayPrompt: Bool {
        item.savedAt < Calendar.current.date(byAdding: .month, value: -4, to: Date()) ?? .distantPast
    }

    private var decayPrompt: some View {
        HStack(spacing: 12) {
            Text("Saved \(item.savedAt.formatted(.relative(presentation: .named))) — still want it?")
                .font(.subheadline)
                .foregroundStyle(.siloInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Not anymore") { archive(.abandoned) }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .tint(.siloSecondaryText)
        }
        .padding(14)
        .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.siloCardBorder, lineWidth: 1)
        }
    }

    // MARK: - Buy bar

    private var buyBar: some View {
        Button {
            if let url = item.url { openURL(url) }
        } label: {
            Label("Open & Buy", systemImage: "bag.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .foregroundStyle(.white)
        .background(.siloClay, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .disabled(item.url == nil)
        .opacity(item.url == nil ? 0.5 : 1)
        .background(.ultraThinMaterial)
        .accessibilityLabel("Open and buy at \(item.sourceDomain ?? "the store")")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit", systemImage: "pencil") { showEdit = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Menu("Add to collection", systemImage: "folder") {
                    ForEach(collections) { collection in
                        Button {
                            item.collection = collection
                            try? modelContext.save()
                        } label: {
                            if item.collection?.id == collection.id {
                                Label(collection.name, systemImage: "checkmark")
                            } else {
                                Text(collection.name)
                            }
                        }
                    }
                    if item.collection != nil {
                        Button("Remove from collection", systemImage: "xmark") {
                            item.collection = nil
                            try? modelContext.save()
                        }
                    }
                    Divider()
                    Button("New collection", systemImage: "plus") {
                        collectionSheet.createNew(filing: item.id)
                    }
                }

                Button("Got it", systemImage: "checkmark.circle") { archive(.gotIt) }
                Button("Not anymore", systemImage: "minus.circle") { archive(.abandoned) }

                Divider()

                Button("Delete", systemImage: "trash", role: .destructive) { deleteItem() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func archive(_ state: ItemState) {
        item.state = state
        if state == .gotIt { Haptics.success() }
        try? modelContext.save()
        dismiss()
    }

    private func deleteItem() {
        if let path = item.imageLocalPath {
            ImageCache.remove(path)
        }
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }

    /// Opportunistic "is it still this price?" check. Skips if we looked recently
    /// (unless the user explicitly pulled to refresh) so revisiting a detail page
    /// doesn't hammer the retailer.
    private func recheckPrice(force: Bool) async {
        if !force,
           let checked = item.priceCheckedAt,
           Date().timeIntervalSince(checked) < 1800 {
            return
        }
        guard !isRechecking, !item.urlString.isEmpty else { return }
        isRechecking = true
        defer { isRechecking = false }

        guard let metadata = await EnrichmentService.fetchMetadata(for: item.urlString),
              let price = metadata.price else { return }

        if item.savedPrice == nil { item.savedPrice = price }
        if item.currencyCode == nil { item.currencyCode = metadata.currencyCode }
        item.currentPrice = price
        item.priceCheckedAt = Date()
        try? modelContext.save()
    }
}
