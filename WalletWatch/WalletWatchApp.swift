import SwiftUI

@main
struct WalletWatchApp: App {
    @StateObject private var store = WatchWalletStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
                .task { store.activate() }
        }
    }
}
