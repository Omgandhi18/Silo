import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

private struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]
    @Query(sort: \SiloCollection.createdAt) private var collections: [SiloCollection]

    @State private var selectedLens: Lens = .all
    @State private var coordinator: EnrichmentCoordinator?
    @State private var collectionSheet = CollectionSheetController()
    @State private var showAddItem = false

    private var activeItems: [Item] {
        items.filter { $0.state == .caught || $0.state == .enriched }
    }

    private var filteredItems: [Item] {
        switch selectedLens {
        case .all:
            activeItems
        case .collection(let id):
            activeItems.filter { $0.collection?.id == id }
        case .unsorted:
            activeItems.filter { $0.collection == nil }
        }
    }

    private var unsortedCount: Int {
        activeItems.filter { $0.collection == nil }.count
    }

    private var selectedCollectionMissing: Bool {
        guard case .collection(let id) = selectedLens else { return false }
        return !collections.contains { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.siloCanvas
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    LensRow(
                        collections: collections,
                        selectedLens: $selectedLens,
                        unsortedCount: unsortedCount,
                        colorScheme: colorScheme
                    )
                    .padding(.top, 10)

                    if filteredItems.isEmpty {
                        EmptyShelfView(hasAnyItems: !activeItems.isEmpty)
                    } else {
                        MasonryGrid(items: filteredItems, collections: collections)
                    }
                }
            }
            .navigationTitle(AppConstants.displayName)
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add link")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ArchiveView()
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .accessibilityLabel("Archive")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .tint(.siloInk)
            .onChange(of: selectedCollectionMissing) { _, missing in
                if missing {
                    selectedLens = .all
                }
            }
            .task {
                if coordinator == nil {
                    coordinator = EnrichmentCoordinator(context: modelContext)
                }
                await coordinator?.sweep()
            }
            .onChange(of: scenePhase) { _, phase in
                // Coming back from the share sheet lands here — enrich whatever
                // just got caught.
                if phase == .active {
                    Task { await coordinator?.sweep() }
                }
            }
            .onChange(of: caughtCount) { _, newValue in
                // A fresh stub arrived while we're already foregrounded.
                if newValue > 0 {
                    Task { await coordinator?.sweep() }
                }
            }
            .sheet(isPresented: $collectionSheet.isPresented) {
                if let mode = collectionSheet.mode {
                    CollectionEditSheet(mode: mode)
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddItemSheet()
            }
        }
        // Injected ABOVE the NavigationStack on purpose: pushed destinations
        // (ItemDetailView) are hosted by the stack and only inherit environment
        // from outside it, not from modifiers on its inner content.
        .environment(collectionSheet)
    }

    private var caughtCount: Int {
        items.filter { $0.state == .caught }.count
    }
}

private enum Lens: Hashable {
    case all
    case collection(UUID)
    case unsorted
}

private struct LensRow: View {
    @Environment(CollectionSheetController.self) private var collectionSheet
    let collections: [SiloCollection]
    @Binding var selectedLens: Lens
    let unsortedCount: Int
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                LensPill(
                    title: "All",
                    isSelected: selectedLens == .all
                ) {
                    selectedLens = .all
                }

                ForEach(collections) { collection in
                    LensPill(
                        title: collection.name,
                        isSelected: selectedLens == .collection(collection.id),
                        dotColor: collection.displayColor(for: colorScheme)
                    ) {
                        selectedLens = .collection(collection.id)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            collectionSheet.edit(collection)
                        }
                    }
                }

                LensPill(
                    title: "Unsorted",
                    isSelected: selectedLens == .unsorted,
                    count: unsortedCount
                ) {
                    selectedLens = .unsorted
                }

                Button {
                    collectionSheet.createNew()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 42, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.siloInk)
                .background(.siloCardSurface, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.siloPillBorder, lineWidth: 1)
                }
                .accessibilityLabel("Create collection")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

private struct LensPill: View {
    let title: String
    let isSelected: Bool
    var dotColor: Color?
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.siloCardSurface)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.siloSecondaryText, in: Circle())
                }
            }
            .foregroundStyle(.siloInk)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(isSelected ? Color.siloCardSurface : Color.clear, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.siloInk.opacity(0.28) : Color.siloPillBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MasonryGrid: View {
    let items: [Item]
    let collections: [SiloCollection]

    private var columns: ([Item], [Item]) {
        var left: [Item] = []
        var right: [Item] = []
        var leftHeight: Double = 0
        var rightHeight: Double = 0

        for item in items {
            let estimate = item.heightEstimate
            if leftHeight <= rightHeight {
                left.append(item)
                leftHeight += estimate
            } else {
                right.append(item)
                rightHeight += estimate
            }
        }

        return (left, right)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 14) {
                LazyVStack(spacing: 14) {
                    ForEach(columns.0) { item in
                        ItemCard(item: item, collections: collections)
                    }
                }
                .frame(maxWidth: .infinity)

                LazyVStack(spacing: 14) {
                    ForEach(columns.1) { item in
                        ItemCard(item: item, collections: collections)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
    }
}

private struct ItemCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(CollectionSheetController.self) private var collectionSheet
    let item: Item
    let collections: [SiloCollection]

    var body: some View {
        NavigationLink {
            ItemDetailView(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
            ProductImagePlaceholder(item: item)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let color = item.collection?.displayColor(for: colorScheme) {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                    }

                    Text(item.title ?? item.fallbackTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.siloInk)
                        .lineLimit(3)
                }

                if let sourceDomain = item.sourceDomain {
                    Text(sourceDomain)
                        .font(.caption)
                        .foregroundStyle(.siloSecondaryText)
                        .lineLimit(1)
                }

                if let price = item.formattedPrice {
                    Text(price)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.siloInk)
                } else if item.state == .caught {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.siloCardBorder)
                        .frame(width: 68, height: 10)
                        .opacity(0.7)
                        .shimmering(active: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.siloCardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu("Add to collection", systemImage: "folder") {
                ForEach(collections) { collection in
                    Button {
                        item.collection = collection
                        Haptics.tap()
                        try? modelContext.save()
                    } label: {
                        // Native menus tint icons with the accent, so a true
                        // per-collection color dot isn't reliable here — a
                        // checkmark marks the current home instead.
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

            Button("Got it", systemImage: "checkmark.circle") {
                item.state = .gotIt
                Haptics.success()
            }

            Button("Not anymore", systemImage: "minus.circle") {
                item.state = .abandoned
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                if let path = item.imageLocalPath {
                    ImageCache.remove(path)
                }
                modelContext.delete(item)
                try? modelContext.save()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }
}

private struct ProductImagePlaceholder: View {
    let item: Item

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.siloCardBorder.opacity(0.72),
                            Color.siloCanvas.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let path = item.imageLocalPath {
                CachedHeroImage(relativePath: path)
            } else {
                Image(systemName: item.state == .caught ? "sparkles" : "shippingbox")
                    .font(.title3)
                    .foregroundStyle(.siloMutedText)
                    .padding(12)
            }
        }
        .aspectRatio(item.placeholderAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shimmering(active: item.state == .caught && item.imageLocalPath == nil)
        .padding([.top, .horizontal], 8)
    }
}

private struct EmptyShelfView: View {
    let hasAnyItems: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()

            Text(hasAnyItems ? "Nothing filed here yet." : "Share a product link to Silo and it'll land here.")
                .font(.system(.title2, design: .serif))
                .fontWeight(.regular)
                .foregroundStyle(.siloInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(hasAnyItems ? "Use a card's long press menu to move it into this collection." : "Share from Safari or any app — tap the share icon, then Silo.")
                .font(.body)
                .foregroundStyle(.siloSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
    }
}

private extension Item {
    var placeholderAspectRatio: CGFloat {
        let seed = abs(id.uuidString.hashValue % 4)
        return [0.82, 0.96, 1.12, 1.28][seed]
    }

    var heightEstimate: Double {
        let titleLength = Double((title ?? fallbackTitle).count)
        return Double(1 / placeholderAspectRatio) * 160 + min(titleLength, 80)
    }
}

extension SiloCollection {
    @MainActor
    func displayColor(for colorScheme: ColorScheme) -> Color {
        Color(hex: colorScheme == .dark ? darkColorHex : colorHex)
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.makeContainer(inMemory: true))
}
