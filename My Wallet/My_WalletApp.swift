//
//  My_WalletApp.swift
//  My Wallet
//
//  Created by Soe Min Thein on 05/09/2026.
//

import SwiftUI
import WalletFeature

@main
struct My_WalletApp: App {
    @StateObject private var bootstrap = AppBootstrap()
    /// Shared by the scene's commands and every window that acts on them.
    @StateObject private var commands = WalletCommandBus()

    var body: some Scene {
        WindowGroup {
            AppRootView(bootstrap: bootstrap, commands: commands)
        }
        .commands { WalletCommands(commands: commands) }
    }
}
