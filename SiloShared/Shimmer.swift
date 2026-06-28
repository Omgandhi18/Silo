import SwiftUI

/// A gentle sweep used to signal a `.caught` item is still being filled in. Calm
/// by design — a soft highlight drifting across the placeholder, never a flashy
/// skeleton. Honors Reduce Motion by falling back to a plain static placeholder.
private struct ShimmerModifier: ViewModifier {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var animating = false

    private var highlight: Color {
        Color.white.opacity(colorScheme == .dark ? 0.06 : 0.35)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: highlight, location: 0.5),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: width * 0.65)
                            .offset(x: animating ? width * 1.1 : -width * 0.75)
                            .animation(
                                .linear(duration: 1.4).repeatForever(autoreverses: false),
                                value: animating
                            )
                    }
                    .allowsHitTesting(false)
                    .clipped()
                    .onAppear { animating = true }
                }
            }
    }
}

extension View {
    /// Sweeps a soft highlight across the view while `active` (e.g. a `.caught`
    /// item that hasn't enriched yet). No-op under Reduce Motion.
    func shimmering(active: Bool) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}
