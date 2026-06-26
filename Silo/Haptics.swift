import UIKit

/// Tiny, calm haptic vocabulary. Used sparingly — a light tap when filing, a
/// success note when something lands in the trophy case. Nothing buzzy.
@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
