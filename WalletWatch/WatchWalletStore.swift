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

    private func apply(_ payload: [String: Any]) {
        guard let received = WalletWatchTransfer.decodeSnapshot(from: payload) else { return }
        snapshot = received
        // Persist so the watch app and its complications survive a relaunch out of range.
        try? WalletSnapshotStore.write(received, groupID: groupID)
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

extension WatchWalletStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            // The phone may have sent context before this side was listening.
            self.apply(session.receivedApplicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.pendingCount = session.outstandingUserInfoTransfers.count
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
                             error: (any Error)?) {
        Task { @MainActor in
            self.pendingCount = session.outstandingUserInfoTransfers.count
            if error != nil { self.lastError = "An expense could not be sent to your iPhone." }
        }
    }
}
