import Combine
import Foundation
import WalletDomain

/// Carries menu and keyboard actions from the app's command menus to whichever window is focused.
///
/// Commands are built once per scene but the views that act on them are deep in the hierarchy, so
/// a small shared object is simpler than threading bindings through every level.
@MainActor
public final class WalletCommandBus: ObservableObject {
    /// Bumped to ask the focused window to open a new-record editor.
    @Published public var newRecordRequests = 0
    @Published public var newRecordKind = RecordKind.expense
    /// Bumped to ask the records list to focus its search field.
    @Published public var searchRequests = 0
    /// Set to move the focused window to a tab.
    @Published public var requestedTab: WalletTab?

    public init() {}

    public func newRecord(kind: RecordKind = .expense) {
        newRecordKind = kind
        newRecordRequests += 1
    }

    public func search() { searchRequests += 1 }

    public func show(_ tab: WalletTab) { requestedTab = tab }
}
