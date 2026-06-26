//
//  SiloApp.swift
//  Silo
//
//  Created by Om Gandhi on 26/06/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct SiloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer = PersistenceController.makeContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}

/// We configure UIKit appearance here, not in `App.init()`. Resolving a font
/// descriptor (`withDesign(.serif)`) talks to the font daemon over XPC; doing
/// that during `App.init` runs it before UIKit/XPC is fully up, which aborts on
/// device (a Mach-message dispatch crash) even though the simulator tolerates
/// it. `didFinishLaunching` is the right, ready moment — and still early enough
/// to style the first navigation bar.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureWordmark()
        return true
    }

    /// Renders the large navigation title (the "Silo" wordmark) in New York
    /// serif — the one deliberate serif touch the spec calls for, matching the
    /// empty-state headlines. Inline titles elsewhere stay SF Pro.
    private func configureWordmark() {
        let largeTitle = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        guard let serif = largeTitle.withDesign(.serif) else { return }

        let weighted = serif.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]
        ])
        let font = UIFont(descriptor: weighted, size: 0)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: font]
    }
}
