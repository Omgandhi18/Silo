import SwiftData
import SwiftUI

/// The two-drawer archive behind the toolbar box. "Got it" is the satisfying
/// trophy case; "Not anymore" is neutral, no judgement. From either, an item can
/// be restored to the active shelf or deleted for good.
struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.savedAt, order: .reverse) private var items: [Item]

    @State private var drawer: Drawer = .gotIt

    enum Drawer: String, CaseIterable, Identifiable {
        case gotIt = "Got it"
        case abandoned = "Not anymore"

        var id: String { rawValue }
        var state: ItemState { self == .gotIt ? .gotIt : .abandoned }
    }

    private var drawerItems: [Item] {
        items.filter { $0.state == drawer.state }
    }

    var body: some View {
        ZStack {
            Color.siloCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Archive drawer", selection: $drawer) {
                    ForEach(Drawer.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if drawerItems.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(drawerItems) { item in
                            ArchiveRow(item: item)
                                .listRowBackground(Color.siloCardSurface)
                                .listRowSeparatorTint(.siloCardBorder)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { restore(item) } label: {
                                        Label("Restore", systemImage: "tray.and.arrow.up")
                                    }
                                    .tint(.siloClay)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(item) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.siloInk)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: drawer == .gotIt ? "trophy" : "wind")
                .font(.largeTitle)
                .foregroundStyle(.siloMutedText)
            Text(drawer == .gotIt ? "Nothing bought yet." : "Nothing let go of yet.")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.siloInk)
            Text(drawer == .gotIt
                 ? "Things you mark “Got it” land here — your quiet trophy case."
                 : "Things you decide against rest here, no fuss.")
                .font(.subheadline)
                .foregroundStyle(.siloSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func restore(_ item: Item) {
        // Send it back to the active shelf. If it never got enriched, drop it to
        // `.caught` so the coordinator's sweep picks it up again.
        let hasData = item.title != nil || item.imageLocalPath != nil || item.savedPrice != nil
        item.state = hasData ? .enriched : .caught
        Haptics.tap()
        try? modelContext.save()
    }

    private func delete(_ item: Item) {
        if let path = item.imageLocalPath {
            ImageCache.remove(path)
        }
        modelContext.delete(item)
        try? modelContext.save()
    }
}

/// A compact archived item: thumbnail, title, source, price. Tapping opens the
/// same detail screen (where it can also be restored or bought).
private struct ArchiveRow: View {
    let item: Item

    var body: some View {
        NavigationLink {
            ItemDetailView(item: item)
        } label: {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.siloInk)
                        .lineLimit(2)
                    if let source = item.sourceDomain {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.siloSecondaryText)
                            .lineLimit(1)
                    }
                    if let price = item.formattedPrice {
                        Text(price)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.siloSecondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.siloCanvas)
            if let path = item.imageLocalPath {
                CachedHeroImage(relativePath: path)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.siloMutedText)
            }
        }
        .frame(width: 54, height: 54)
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(.siloCardBorder, lineWidth: 1)
        }
    }
}
