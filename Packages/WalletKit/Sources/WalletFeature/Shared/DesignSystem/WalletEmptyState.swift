import SwiftUI

/// One empty-state shape for the whole app, so every screen explains itself the same way.
///
/// Wraps `ContentUnavailableView` rather than replacing it, keeping the system's layout,
/// Dynamic Type behavior and VoiceOver grouping.
struct WalletEmptyState: View {
    let title: String
    let symbol: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

/// The loading counterpart, so spinners read consistently too.
struct WalletLoadingState: View {
    let message: String

    var body: some View {
        ProgressView(message)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WalletEmptyState(title: "No records yet", symbol: "list.bullet.rectangle",
                     message: "Add an expense, income, or transfer.",
                     actionTitle: "Add Record") {}
}
