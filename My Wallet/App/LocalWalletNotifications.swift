import Foundation
import UserNotifications
import WalletDomain

@MainActor
final class LocalWalletNotifications: NSObject, WalletNotificationClient, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let scheduledKey = "wallet.scheduledPlanningNotices"
    private let deliveredKey = "wallet.deliveredPlanningNotices"

    override init() {
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func synchronize(_ notifications: [WalletNotification], managing prefixes: [String]) async throws {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        var history = Set(defaults.stringArray(forKey: deliveredKey) ?? [])
        history.formUnion(delivered.map(\.request.identifier))
        let scheduled = defaults.dictionary(forKey: scheduledKey) as? [String: Double] ?? [:]
        // A passed scheduled request no longer pending has fired, even if the user
        // already cleared it from Notification Center before reopening the app.
        for (id, timestamp) in scheduled where timestamp <= Date().timeIntervalSince1970 && !pendingIDs.contains(id) {
            history.insert(id)
        }
        let selected = notifications.filter { !history.contains($0.id) }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }.prefix(60)
        let selectedIDs = Set(selected.map(\.id))
        // Only this caller's notices are cleared; other sources keep theirs.
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { request in
            prefixes.contains { request.identifier.hasPrefix($0) } && !selectedIDs.contains(request.identifier)
        }.map(\.identifier))
        var nextScheduled: [String: Double] = [:]
        for notice in selected {
            if history.contains(notice.id) { continue }
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            let trigger: UNNotificationTrigger?
            if let date = notice.date, date > Date() {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
            } else { trigger = nil }
            try await center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
            if trigger == nil { history.insert(notice.id) }
            else { nextScheduled[notice.id] = notice.date?.timeIntervalSince1970 }
        }
        // Keep delivery receipts even after clearing system notifications; one alert per threshold/occurrence.
        defaults.set(Array(history).sorted(), forKey: deliveredKey)
        defaults.set(nextScheduled, forKey: scheduledKey)
    }
}
