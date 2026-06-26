import SwiftUI
import UIKit

enum Theme {
    static let collectionSwatches: [CollectionSwatch] = [
        CollectionSwatch(name: "Clay", lightHex: "#BC6B4A", darkHex: "#C97C5A"),
        CollectionSwatch(name: "Amber", lightHex: "#C49A48", darkHex: "#D2A95C"),
        CollectionSwatch(name: "Sage", lightHex: "#8B9A6B", darkHex: "#9CAB7C"),
        CollectionSwatch(name: "Teal", lightHex: "#5A9488", darkHex: "#6FA89B"),
        CollectionSwatch(name: "Dusty blue", lightHex: "#6F8CA8", darkHex: "#82A0BB"),
        CollectionSwatch(name: "Slate", lightHex: "#7E8693", darkHex: "#9098A5"),
        CollectionSwatch(name: "Plum", lightHex: "#94708E", darkHex: "#A8839F"),
        CollectionSwatch(name: "Rose", lightHex: "#BE8294", darkHex: "#CB95A6")
    ]
}

struct CollectionSwatch: Identifiable, Hashable {
    let name: String
    let lightHex: String
    let darkHex: String

    var id: String { name }
}

extension ShapeStyle where Self == Color {
    static var siloCanvas: Color {
        Color(light: "#F4EEE4", dark: "#1C1916")
    }

    static var siloCardSurface: Color {
        Color(light: "#FBF7F0", dark: "#262019")
    }

    static var siloCardBorder: Color {
        Color(light: "#E7DFD2", dark: "#342D24")
    }

    static var siloPillBorder: Color {
        Color(light: "#E2D9CB", dark: "#3A3228")
    }

    static var siloInk: Color {
        Color(light: "#2C2823", dark: "#EDE6D9")
    }

    static var siloSecondaryText: Color {
        Color(light: "#6B6359", dark: "#7C7468")
    }

    static var siloMutedText: Color {
        Color(light: "#8A8175", dark: "#6B6357")
    }

    static var siloStruckPrice: Color {
        Color(light: "#A39A8C", dark: "#6B6357")
    }

    static var siloClay: Color {
        Color(light: "#C2663F", dark: "#D17A52")
    }
}

extension Color {
    nonisolated init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double

        switch cleaned.count {
        case 8:
            red = Double((value & 0xFF00_0000) >> 24) / 255
            green = Double((value & 0x00FF_0000) >> 16) / 255
            blue = Double((value & 0x0000_FF00) >> 8) / 255
            opacity = Double(value & 0x0000_00FF) / 255
        case 6:
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
            opacity = 1
        default:
            red = 0
            green = 0
            blue = 0
            opacity = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// A scheme-adaptive color.
    ///
    /// `nonisolated` is load-bearing: UIKit invokes the dynamic-provider closure
    /// off the main thread (SwiftUI's async renderer resolves colors there). The
    /// project defaults to `MainActor` isolation, so without this the closure is
    /// inferred `@MainActor` and the Swift runtime traps when it runs off-main.
    /// We also resolve straight to `UIColor` from hex — no `Color`→`UIColor`
    /// bridging inside the provider, which would drag main-actor work back in.
    nonisolated init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(siloHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    /// Parses `#RRGGBB` / `#RRGGBBAA` into a `UIColor`. Mirrors `Color(hex:)` but
    /// stays in UIKit so it's safe to call from a dynamic-color provider.
    nonisolated convenience init(siloHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red, green, blue, alpha: CGFloat
        switch cleaned.count {
        case 8:
            red = CGFloat((value & 0xFF00_0000) >> 24) / 255
            green = CGFloat((value & 0x00FF_0000) >> 16) / 255
            blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
            alpha = CGFloat(value & 0x0000_00FF) / 255
        case 6:
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        default:
            red = 0; green = 0; blue = 0; alpha = 1
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
