import SwiftUI

/// The shared "it landed" moment, used by both the in-app Add sheet and the
/// Share Extension. A single product card materialises with a little sparkle as
/// its details arrive, a status line up top, and collection chips below so the
/// find can be filed without opening the app.
///
/// Presentational only: the host owns persistence and runs enrichment, feeding
/// results in through the `SavedSheetModel` and reacting to the two closures.
struct SavedProductSheet: View {
    @Bindable var model: SavedSheetModel
    var onSelectCollection: (UUID?) -> Void
    var onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.siloCanvas.ignoresSafeArea()

            VStack(spacing: 22) {
                statusRow

                card
                    .scaleEffect(appeared ? 1 : 0.92)
                    .opacity(appeared ? 1 : 0)

                if !model.collections.isEmpty {
                    chipsRow
                        .padding(.top, 8)
                }

                doneButton
            }
            .frame(maxWidth: 360)
            .padding(28)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { appeared = true }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .done { Haptics.success() }
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            if model.phase == .enriching {
                ProgressView()
                    .controlSize(.small)
                    .tint(.siloSecondaryText)
                Text("Filling in the details…")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.siloClay)
                Text("Saved to \(AppConstants.displayName)")
            }
        }
        .font(.headline)
        .foregroundStyle(.siloInk)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }

    // MARK: - Product card (mirrors the home shelf card)

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardImage

            VStack(alignment: .leading, spacing: 6) {
                Text(model.title ?? model.domain ?? "Saved link")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.siloInk)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if let domain = model.domain {
                    Text(domain)
                        .font(.caption)
                        .foregroundStyle(.siloSecondaryText)
                        .lineLimit(1)
                }

                if let price = model.priceText {
                    Text(price)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.siloInk)
                        .transition(.opacity)
                } else if model.phase == .enriching {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.siloCardBorder)
                        .frame(width: 64, height: 10)
                        .opacity(0.7)
                        .shimmering(active: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 210)
        .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(.siloCardBorder, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let color = selectedChipColor {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.10), radius: 22, y: 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.selectedCollectionID)
    }

    private var cardImage: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Color.siloCardBorder.opacity(0.72), Color.siloCanvas.opacity(0.82)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1.0, contentMode: .fit)
            .overlay {
                if let path = model.imageRelativePath {
                    CachedHeroImage(relativePath: path)
                        .transition(.opacity)
                } else {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.siloMutedText)
                }
            }
            .overlay {
                SparkleBurst(trigger: model.phase == .done)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shimmering(active: model.phase == .enriching && model.imageRelativePath == nil)
            .padding([.top, .horizontal], 8)
            .animation(.easeOut(duration: 0.3), value: model.imageRelativePath)
    }

    // MARK: - Collection chips

    private var chipsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File into")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.siloSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(id: nil, name: "Unsorted", color: nil)
                    ForEach(model.collections) { collection in
                        chip(id: collection.id,
                             name: collection.name,
                             color: collection.color(for: colorScheme))
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(id: UUID?, name: String, color: Color?) -> some View {
        let isSelected = model.selectedCollectionID == id
        return Button {
            Haptics.tap()
            model.selectedCollectionID = id
            onSelectCollection(id)
        } label: {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.siloInk)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(isSelected ? Color.siloCardSurface : Color.clear, in: Capsule())
            .overlay {
                Capsule().stroke(
                    isSelected ? Color.siloClay.opacity(0.55) : Color.siloPillBorder,
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Done

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.siloClay, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var selectedChipColor: Color? {
        guard let id = model.selectedCollectionID else { return nil }
        return model.collections.first { $0.id == id }?.color(for: colorScheme)
    }
}

// MARK: - Model

@MainActor
@Observable
final class SavedSheetModel {
    enum Phase { case enriching, done }

    var phase: Phase
    var title: String?
    var domain: String?
    var priceText: String?
    var imageRelativePath: String?
    var collections: [CollectionChip]
    var selectedCollectionID: UUID?

    init(phase: Phase = .enriching,
         title: String? = nil,
         domain: String? = nil,
         priceText: String? = nil,
         imageRelativePath: String? = nil,
         collections: [CollectionChip] = [],
         selectedCollectionID: UUID? = nil) {
        self.phase = phase
        self.title = title
        self.domain = domain
        self.priceText = priceText
        self.imageRelativePath = imageRelativePath
        self.collections = collections
        self.selectedCollectionID = selectedCollectionID
    }
}

/// A lightweight, SwiftData-free view of a collection so the shared card never
/// has to reach into the model layer.
struct CollectionChip: Identifiable, Hashable {
    let id: UUID
    let name: String
    let lightHex: String
    let darkHex: String

    func color(for scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? darkHex : lightHex)
    }
}

// MARK: - Sparkles

/// A one-shot sparkle flourish that plays whenever `trigger` flips true — the
/// little bit of "magic" as the real product surfaces.
private struct SparkleBurst: View {
    let trigger: Bool

    // Position (0–1) and point size for each spark.
    private let sparks: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.16, 0.22, 15), (0.84, 0.16, 11), (0.80, 0.78, 17),
        (0.22, 0.82, 12), (0.52, 0.10, 9)
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(sparks.indices, id: \.self) { i in
                let spark = sparks[i]
                Image(systemName: "sparkle")
                    .font(.system(size: spark.size))
                    .foregroundStyle(.siloClay)
                    .position(x: geo.size.width * spark.x, y: geo.size.height * spark.y)
                    .phaseAnimator([0, 1, 2], trigger: trigger) { view, phase in
                        view
                            .scaleEffect(phase == 0 ? 0.1 : (phase == 1 ? 1.0 : 0.5))
                            .opacity(phase == 1 ? 1 : 0)
                    } animation: { phase in
                        .easeOut(duration: phase == 1 ? 0.28 : 0.45)
                    }
            }
        }
        .allowsHitTesting(false)
    }
}
