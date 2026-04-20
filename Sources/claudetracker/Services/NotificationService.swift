import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var observer: NSObjectProtocol?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await self.refreshAuthorization() }
        observer = NotificationCenter.default.addObserver(
            forName: .statuslineDidUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkThresholds() }
        }
    }

    deinit {
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Authorization

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.authorizationStatus = settings.authorizationStatus
    }

    /// Prompt the user for notification permission. Idempotent — the system only
    /// shows a dialog when status is .notDetermined.
    func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshAuthorization()
    }

    // MARK: - Threshold checks

    private struct ThresholdKey {
        let windowLabel: String   // "5-hour block" / "7-day window"
        let enabledKey: String    // SettingsKey.notify*
        let firedKey: String      // SettingsKey.lastFired*
        let threshold: Double     // 80 / 95
        let identifier: String    // unique UNNotificationRequest id prefix
    }

    private func checkThresholds() {
        guard let bridge = BridgeAccess.shared else { return }
        guard bridge.isFresh, let rl = bridge.snapshot?.rateLimits else { return }

        if let pct = rl.fiveHour?.usedPercentage,
           let resetTs = rl.fiveHour?.resetsAt {
            evaluate(pct: pct, resetAt: resetTs, windowLabel: "5-hour block",
                     thresholds: [
                        ThresholdKey(windowLabel: "5-hour block",
                                     enabledKey: SettingsKey.notify5h80,
                                     firedKey: SettingsKey.lastFired5h80,
                                     threshold: 80, identifier: "5h-80"),
                        ThresholdKey(windowLabel: "5-hour block",
                                     enabledKey: SettingsKey.notify5h95,
                                     firedKey: SettingsKey.lastFired5h95,
                                     threshold: 95, identifier: "5h-95"),
                     ])
        }
        if let pct = rl.sevenDay?.usedPercentage,
           let resetTs = rl.sevenDay?.resetsAt {
            evaluate(pct: pct, resetAt: resetTs, windowLabel: "7-day window",
                     thresholds: [
                        ThresholdKey(windowLabel: "7-day window",
                                     enabledKey: SettingsKey.notify7d80,
                                     firedKey: SettingsKey.lastFired7d80,
                                     threshold: 80, identifier: "7d-80"),
                        ThresholdKey(windowLabel: "7-day window",
                                     enabledKey: SettingsKey.notify7d95,
                                     firedKey: SettingsKey.lastFired7d95,
                                     threshold: 95, identifier: "7d-95"),
                     ])
        }
    }

    private func evaluate(pct: Double, resetAt: TimeInterval, windowLabel: String, thresholds: [ThresholdKey]) {
        let defaults = UserDefaults.standard
        for t in thresholds {
            guard defaults.bool(forKey: t.enabledKey) else { continue }
            guard pct >= t.threshold else { continue }
            let lastFiredResetTs = defaults.double(forKey: t.firedKey)
            // If we've already fired for this particular resetAt, skip.
            // When the window resets, resetAt changes, so the dedup clears itself.
            if lastFiredResetTs == resetAt { continue }
            fire(t, pct: pct, resetAt: resetAt)
            defaults.set(resetAt, forKey: t.firedKey)
        }
    }

    private func fire(_ t: ThresholdKey, pct: Double, resetAt: TimeInterval) {
        let resetDate = Date(timeIntervalSince1970: resetAt)
        let content = UNMutableNotificationContent()
        content.title = "\(t.windowLabel) at \(Int(pct.rounded()))%"
        content.body = "Resets \(Fmt.dayTime(resetDate))"
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "\(t.identifier)-\(Int(resetAt))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

/// Present notifications even when the app is foreground (menubar apps are
/// effectively always "foreground" from the system's POV).
extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Narrow hook so NotificationService can read the current StatuslineBridge
/// snapshot without being coupled to App.swift construction order.
enum BridgeAccess {
    @MainActor static var shared: StatuslineBridge?
}
