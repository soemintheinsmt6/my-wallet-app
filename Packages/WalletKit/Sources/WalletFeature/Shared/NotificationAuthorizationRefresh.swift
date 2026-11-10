import SwiftUI

extension View {
    /// Re-checks notification permission when the view appears and whenever the app returns to
    /// the foreground, so a permission granted in Settings hides "Enable System Notifications".
    ///
    /// Attach it to a row that is always shown, not to the button it controls: a hidden button
    /// would never run the check that brings it back.
    func refreshesNotificationAuthorization(_ refresh: @escaping () async -> Void) -> some View {
        modifier(NotificationAuthorizationRefresh(refresh: refresh))
    }
}

private struct NotificationAuthorizationRefresh: ViewModifier {
    let refresh: () async -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
    }
}
