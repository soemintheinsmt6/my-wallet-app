import Combine
import Foundation
import WalletDomain
import WatchConnectivity
#if canImport(WidgetKit)
    import WidgetKit
#endif

/// The watch half of the link, and the watch's only source of wallet data.
///
/// The store lives on the phone, so the watch keeps the last snapshot it received and proposes
/// expenses rather than writing them. Queued expenses survive being out of range because
/// `transferUserInfo` delivers in order once the phone is reachable again.
@MainActor
final class WatchWalletStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WalletSnapshot?
    @Published private(set) var isReachable = false
    @Published private(set) var pendingCount = 0
    @Published var lastError: String?

    private var session: WCSession?

    /// Shared with the complication extension, which cannot use WatchConnectivity itself.
    private let groupID = WalletSnapshotStore.appGroupID

    override init() {
        super.init()
        snapshot = WalletSnapshotStore.read(groupID: groupID)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        isReachable = session.isReachable
    }

    /// Sends an expense to the phone.
    ///
    /// Uses `transferUserInfo` rather than `sendMessage` so a capture made away from the phone is
    /// queued and delivered later instead of failing outright.
    func add(amount: Decimal, accountID: UUID, categoryID: UUID?) {
        guard let session else { return }
        let expense = WalletSnapshot.QuickExpense(amount: amount, accountID: accountID,
                                                  categoryID: categoryID)
        do {
            session.transferUserInfo(try WalletWatchTransfer.encode(expense: expense))
            pendingCount = session.outstandingUserInfoTransfers.count
            lastError = nil
        } catch {
            lastError = "That expense could not be queued."
        }
    }

    private func apply(_ received: WalletSnapshot?) {
        guard let received else { return }
        snapshot = received
        // Persist so the watch app and its complications survive a relaunch out of range.
        try? WalletSnapshotStore.write(received, groupID: groupID)
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// Delegate callbacks arrive on a WatchConnectivity queue. `WCSession` and its `[String: Any]`
/// payloads are not `Sendable`, so each callback reads plain values there — reachability, counts,
/// the decoded snapshot — and hands only those to the main actor.
extension WatchWalletStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: (any Error)?) {
        let reachable = session.isReachable
        // The phone may have sent context before this side was listening.
        let received = WalletWatchTransfer.decodeSnapshot(from: session.receivedApplicationContext)
        Task { @MainActor in
            self.isReachable = reachable
            self.apply(received)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let received = WalletWatchTransfer.decodeSnapshot(from: context)
        Task { @MainActor in self.apply(received) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        let pending = session.outstandingUserInfoTransfers.count
        Task { @MainActor in
            self.isReachable = reachable
            self.pendingCount = pending
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
                             error: (any Error)?) {
        let pending = session.outstandingUserInfoTransfers.count
        let failed = error != nil
        Task { @MainActor in
            self.pendingCount = pending
            if failed { self.lastError = "An expense could not be sent to your iPhone." }
        }
    }
}
