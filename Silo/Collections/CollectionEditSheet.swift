import SwiftData
import SwiftUI

/// The one sheet for both making and editing a collection — "same component,
/// two doors" per the spec. Just a name and a curated swatch; no free color
/// picker, because the whole point of the palette is that any combination stays
/// harmonious.
struct CollectionEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let mode: CollectionSheetMode

    @State private var name: String
    @State private var selectedSwatch: CollectionSwatch
    @State private var showDeleteConfirm = false

    init(mode: CollectionSheetMode) {
        self.mode = mode
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _selectedSwatch = State(initialValue: Theme.collectionSwatches[0])
        case .edit(let collection):
            _name = State(initialValue: collection.name)
            let match = Theme.collectionSwatches.first { $0.lightHex == collection.colorHex }
            _selectedSwatch = State(initialValue: match ?? Theme.collectionSwatches[0])
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.siloCanvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 28) {
                    nameField
                    swatchPicker

                    if isEditing {
                        deleteButton
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle(isEditing ? "Edit collection" : "New collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .tint(.siloInk)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.siloSecondaryText)

            TextField("e.g. Kitchen, Gifts, Someday", text: $name)
                .font(.title3)
                .foregroundStyle(.siloInk)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { if !trimmedName.isEmpty { save() } }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(.siloCardSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.siloCardBorder, lineWidth: 1)
                }
        }
    }

    private var swatchPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.siloSecondaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 46), spacing: 14)],
                spacing: 14
            ) {
                ForEach(Theme.collectionSwatches) { swatch in
                    SwatchDot(
                        swatch: swatch,
                        isSelected: swatch == selectedSwatch,
                        colorScheme: colorScheme
                    ) {
                        selectedSwatch = swatch
                    }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete collection", systemImage: "trash")
                .font(.subheadline)
        }
        .tint(.siloClay)
        .confirmationDialog(
            "Delete this collection? Items in it return to Unsorted — they're never deleted.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete collection", role: .destructive) { deleteCollection() }
        }
    }

    // MARK: - Actions

    private func save() {
        guard !trimmedName.isEmpty else { return }

        switch mode {
        case .create(let fileItemID):
            let collection = SiloCollection(
                name: trimmedName,
                colorHex: selectedSwatch.lightHex,
                darkColorHex: selectedSwatch.darkHex
            )
            modelContext.insert(collection)

            // File the originating item, if this sheet was opened from a card.
            if let fileItemID {
                let descriptor = FetchDescriptor<Item>(
                    predicate: #Predicate { $0.id == fileItemID }
                )
                if let item = try? modelContext.fetch(descriptor).first {
                    item.collection = collection
                }
            }

        case .edit(let collection):
            collection.name = trimmedName
            collection.colorHex = selectedSwatch.lightHex
            collection.darkColorHex = selectedSwatch.darkHex
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteCollection() {
        guard case .edit(let collection) = mode else { return }
        // Items un-file themselves via the model's `.nullify` delete rule.
        modelContext.delete(collection)
        try? modelContext.save()
        dismiss()
    }
}

/// A single tappable swatch in the picker. Shows the scheme-appropriate hue with
/// a ring when chosen.
private struct SwatchDot: View {
    let swatch: CollectionSwatch
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    private var color: Color {
        Color(hex: colorScheme == .dark ? swatch.darkHex : swatch.lightHex)
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 38, height: 38)
                .overlay {
                    Circle().stroke(.siloCanvas, lineWidth: isSelected ? 3 : 0)
                }
                .overlay {
                    Circle()
                        .stroke(.siloInk, lineWidth: isSelected ? 2 : 0)
                        .padding(-2)
                }
                .scaleEffect(isSelected ? 1.05 : 1)
                .animation(.snappy(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
