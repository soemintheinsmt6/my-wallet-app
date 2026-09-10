import Foundation
import WalletDomain
import WatchConnectivity

/// The phone half of the watch link.
///
/// Sends the wallet snapshot to the watch and writes expenses the watch captured. The watch never
/// touches the store — it lives on the phone — so the watch only ever proposes a record and this
/// side saves it through the normal use case.
@MainActor
final class PhoneWatchConnector: NSObject {
    /// Set by the app so incoming expenses can be written.
    var saveExpense: ((WalletSnapshot.QuickExpense) async -> Void)?

    private var session: WCSession?
    private var lastSent: WalletSnapshot?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// Mirrors the snapshot to the watch.
    ///
    /// `updateApplicationContext` replaces any earlier pending payload and is delivered in the
    /// background, which is exactly right for "latest state wins" — a queue of stale snapshots
    /// would be worse than none.
    func send(_ snapshot: WalletSnapshot) {
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
            guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard snapshot != lastSent else { return }
        do {
            try session.updateApplicationContext(try WalletWatchTransfer.encode(snapshot: snapshot))
            lastSent = snapshot
        } catch {
            // A failed mirror is not worth surfacing: the next change tries again.
        }
    }
}

extension PhoneWatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: (any Error)?) {}

    #if os(iOS)
        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

        /// Re-activate so a newly paired watch keeps receiving updates.
        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            WCSession.default.activate()
        }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let expense = WalletWatchTransfer.decodeExpense(from: userInfo) else { return }
        Task { @MainActor in await saveExpense?(expense) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let expense = WalletWatchTransfer.decodeExpense(from: message)
        // Acknowledge receipt synchronously; the reply cannot be carried into the main actor, and
        // the watch only needs to know the payload arrived, not that the write finished.
        replyHandler(["ok": expense != nil])
        guard let expense else { return }
        Task { @MainActor in await saveExpense?(expense) }
    }
}
