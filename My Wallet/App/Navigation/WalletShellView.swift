import CoreSpotlight
import SwiftUI
import WalletDomain
import WalletFeature

/// Chooses the layout for the window's width: tabs when compact, a sidebar and split view when
/// regular.
///
/// Both layouts share the same selection and pending-add state, so switching — rotating an iPad,
/// or resizing a macOS window — keeps the user where they were.
struct WalletShellView: View {
    let dependencies: AppDependencies
    @ObservedObject var settings: SettingsViewModel
    @ObservedObject var commands: WalletCommandBus
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = WalletTab.home
    @State private var pendingAdd: RecordKind?

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        private var isWide: Bool { horizontalSizeClass == .regular }
    #else
        private let isWide = true
    #endif

    var body: some View {
        Group {
            if isWide {
                WalletSidebarView(dependencies: dependencies, settings: settings, commands: commands,
                                  selection: $selection, pendingAdd: $pendingAdd)
            } else {
                WalletTabsView(dependencies: dependencies, settings: settings,
                               selection: $selection, pendingAdd: $pendingAdd)
            }
        }
        // Reaches the record editor and detail without threading through every presenter.
        .environment(\.currencyViewModel, dependencies.currencyViewModel)
        .environment(\.receiptUseCases, dependencies.receiptUseCases)
        .environment(\.categorySymbolStore, dependencies.categorySymbolStore)
        .modifier(WalletThemeModifier(theme: dependencies.themeViewModel))
        // Discard open drafts/navigation in every window after a successful reset.
        .id(settings.resetGeneration)
        .disabled(settings.isResetting)
        .task { await dependencies.planningViewModel.observe() }
        .task { dependencies.snapshotCoordinator.start() }
        .task { dependencies.watchConnector.activate() }
        .onChange(of: dependencies.recordsViewModel.accounts.map(\.name)) { _, _ in indexSpotlight() }
        .onChange(of: dependencies.recordsViewModel.categories.map(\.name)) { _, _ in indexSpotlight() }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let tab = WalletSpotlightIndexer.destination(for: identifier) else { return }
            selection = tab
        }
        .onOpenURL { url in open(url) }
        // Menu and keyboard commands act on whichever window is frontmost.
        .onChange(of: commands.newRecordRequests) { _, _ in
            selection = .home
            pendingAdd = commands.newRecordKind
        }
        .onChange(of: commands.requestedTab) { _, tab in
            guard let tab else { return }
            selection = tab
            commands.requestedTab = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await dependencies.planningViewModel.refresh(generate: true) } }
        }
    }

    private func indexSpotlight() {
        dependencies.spotlightIndexer.index(accounts: dependencies.recordsViewModel.accounts,
                                            categories: dependencies.recordsViewModel.categories)
    }

    /// Routes a widget deep link. Quick-add lands on Home, which owns the editor sheet.
    private func open(_ url: URL) {
        guard let link = WalletDeepLink(url: url) else { return }
        switch link {
        case .home: selection = .home
        case .records: selection = .records
        case .statistics: selection = .statistics
        case .planning: selection = .planning
        case .addRecord(let kind):
            selection = .home
            pendingAdd = kind
        }
    }
}
