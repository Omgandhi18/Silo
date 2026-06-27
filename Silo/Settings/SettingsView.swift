import StoreKit
import SwiftUI

/// Light settings: a default currency, ways to reach the developer, and the
/// version stamp. Kept deliberately small — Silo has no accounts to manage.
struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @AppStorage(AppConstants.defaultCurrencyKey)
    private var defaultCurrency = Locale.current.currency?.identifier ?? "USD"

    private static let developerEmail = "devilgandhi@gmail.com"

    /// Major currencies up top; the device's own currency is folded in if it
    /// isn't already listed, so nobody's stuck without their own.
    private var currencyOptions: [String] {
        let common = ["USD", "EUR", "GBP", "INR", "JPY", "CAD", "AUD",
                      "CHF", "CNY", "SEK", "SGD", "AED", "BRL", "ZAR"]
        if !common.contains(defaultCurrency) {
            return [defaultCurrency] + common
        }
        return common
    }

    var body: some View {
        ZStack {
            Color.siloCanvas.ignoresSafeArea()

            List {
                Section {
                    Picker("Default currency", selection: $defaultCurrency) {
                        ForEach(currencyOptions, id: \.self) { code in
                            Text(label(for: code)).tag(code)
                        }
                    }
                    .listRowBackground(Color.siloCardSurface)
                } header: {
                    Text("Preferences").foregroundStyle(.siloSecondaryText)
                } footer: {
                    Text("Used when a saved item doesn't carry its own currency.")
                        .foregroundStyle(.siloMutedText)
                }

                Section {
                    Button {
                        contactDeveloper()
                    } label: {
                        Label("Contact the developer", systemImage: "envelope")
                    }
                    .listRowBackground(Color.siloCardSurface)

                    Button {
                        requestReview()
                    } label: {
                        Label("Rate Silo", systemImage: "star")
                    }
                    .listRowBackground(Color.siloCardSurface)
                } header: {
                    Text("Support").foregroundStyle(.siloSecondaryText)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .foregroundStyle(.siloInk)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { versionStamp }
        .tint(.siloInk)
    }

    private var versionStamp: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return Text("\(AppConstants.displayName) \(version) (\(build))")
            .font(.caption)
            .foregroundStyle(.siloMutedText)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
    }

    private func label(for code: String) -> String {
        if let name = Locale.current.localizedString(forCurrencyCode: code) {
            return "\(code) — \(name)"
        }
        return code
    }

    private func contactDeveloper() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.developerEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Silo Feedback")]
        if let url = components.url { openURL(url) }
    }
}
