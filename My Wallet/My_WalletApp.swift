//
//  My_WalletApp.swift
//  My Wallet
//
//  Created by Soe Min Thein on 05/09/2026.
//

import SwiftUI

@main
struct My_WalletApp: App {
    @StateObject private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            AppRootView(bootstrap: bootstrap)
        }
    }
}
