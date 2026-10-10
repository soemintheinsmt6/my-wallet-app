import SwiftUI
import WalletDomain

/// Arranges the dashboard: which cards show, and in what order.
struct DashboardSettingsView: View {
    @ObservedObject var dashboard: DashboardViewModel
    let accounts: [Account]
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    private var configuration: DashboardConfiguration { dashboard.configuration }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WalletMenuPicker("Period", selection: Binding(
                        get: { configuration.period },
                        set: { dashboard.configuration.period = $0 }
                    ), value: configuration.period.title) {
                        ForEach(DashboardPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    WalletMenuPicker("Accounts", selection: Binding(
                        get: { configuration.accountID },
                        set: { dashboard.configuration.accountID = $0 }
                    ), value: accounts.first { $0.id == configuration.accountID }?.name ?? "All accounts") {
                        Text("All accounts").tag(nil as UUID?)
                        ForEach(accounts.filter { !$0.settings.excludeFromStats }) {
                            Text($0.name).tag(Optional($0.id))
                        }
                    }
                } header: {
                    Text("Scope")
                } footer: {
                    Text("Applies to every figure on the dashboard. Accounts excluded from statistics never appear.")
                }

                Section {
                    ForEach(configuration.arranged) { card in
                        HStack(spacing: WalletMetrics.medium) {
                            WalletIconTile(symbol: card.symbol,
                                           color: configuration.isVisible(card) ? .accentColor : .gray)
                            Text(card.title)
                                .foregroundStyle(configuration.isVisible(card) ? .primary : .secondary)
                            Spacer(minLength: WalletMetrics.small)
                            Toggle("", isOn: Binding(
                                get: { configuration.isVisible(card) },
                                set: { dashboard.configuration.setVisible(card, $0) }
                            ))
                            .labelsHidden()
                            .accessibilityLabel("Show \(card.title)")
                        }
                        .frame(minHeight: WalletMetrics.touchTarget)
                    }
                    .onMove { source, destination in
                        dashboard.configuration.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("Cards")
                } footer: {
                    Text("Drag to reorder. A card with nothing to show — no budgets, no bills — stays hidden until it has content.")
                }

                Section {
                    Button("Reset to Default", role: .destructive) { confirmingReset = true }
                }
            }
            // Reordering needs edit mode on iOS for the drag handles; macOS lists reorder without it.
            #if os(iOS)
                .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Arrange Dashboard")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Reset the dashboard?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { dashboard.reset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restores the default cards and order. Your records are untouched.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}
