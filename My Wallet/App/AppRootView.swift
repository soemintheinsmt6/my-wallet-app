import SwiftUI
import WalletFeature

struct AppRootView: View {
    @ObservedObject var bootstrap: AppBootstrap
    @State private var attempt = 0

    var body: some View {
        Group {
            if let dependencies = bootstrap.dependencies {
                AccountsView(viewModel: dependencies.accountsViewModel)
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
    }
}
