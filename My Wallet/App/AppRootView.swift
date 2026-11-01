import SwiftUI
import WalletFeature

struct AppRootView: View {
    @ObservedObject var bootstrap: AppBootstrap
    @ObservedObject var commands: WalletCommandBus
    @State private var attempt = 0
    @State private var hasOnboarded = OnboardingViewModel.hasCompleted()
    @AppStorage(WalletPreferenceKeys.appearance) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        Group {
            if let dependencies = bootstrap.dependencies {
                // The gate renders the lock screen instead of the tabs, so no balance is
                // readable — or captured in the app switcher — while locked.
                AppLockGate(viewModel: dependencies.appLockViewModel) {
                    if hasOnboarded {
                        WalletShellView(dependencies: dependencies,
                                        settings: dependencies.settingsViewModel,
                                        commands: commands)
                    } else {
                        OnboardingView(viewModel: dependencies.onboardingViewModel,
                                       categories: dependencies.categoriesViewModel)
                            .transition(.opacity)
                    }
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
                WalletLaunchView()
            }
        }
        .task(id: attempt) {
            await bootstrap.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .walletOnboardingFinished)) { _ in
            withAnimation { hasOnboarded = true }
        }
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
}
