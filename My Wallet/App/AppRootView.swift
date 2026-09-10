import SwiftUI
import WalletFeature

struct AppRootView: View {
    @ObservedObject var bootstrap: AppBootstrap
    @State private var attempt = 0
    @AppStorage(WalletPreferenceKeys.appearance) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        Group {
            if let dependencies = bootstrap.dependencies {
                // The gate renders the lock screen instead of the tabs, so no balance is
                // readable — or captured in the app switcher — while locked.
                AppLockGate(viewModel: dependencies.appLockViewModel) {
                    WalletTabsView(dependencies: dependencies, settings: dependencies.settingsViewModel)
                }
            } else if let startupError = bootstrap.errorMessage {
                ContentUnavailableView {
                    Label("Unable to Open Wallet", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(startupError)
                } actions: {
                    Button("Retry") { attempt += 1 }
                }
            } else {
                ProgressView("Opening wallet…")
            }
        }
        .task(id: attempt) {
            await bootstrap.load()
        }
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
}
