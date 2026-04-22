import SwiftUI
import AppKit

@main
struct ClaudeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bridge = StatuslineBridge()
    @StateObject private var usage = UsageStore()
    @StateObject private var sessions = SessionsBridge()

    init() {
        // NotificationService reads bridge snapshots through this shared pointer
        // (set inside body construction below via a side effect).
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(bridge)
                .environmentObject(usage)
                .environmentObject(sessions)
                .onAppear {
                    BridgeAccess.shared = bridge
                }
        } label: {
            MenuBarLabel(bridge: bridge, usage: usage)
                .onAppear {
                    BridgeAccess.shared = bridge
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }

        WindowGroup(id: "session-detail", for: SessionDetailTarget.self) { target in
            if let value = target.wrappedValue {
                SessionDetailView(target: value)
                    .frame(minWidth: 640, minHeight: 480)
            }
        }
        .defaultSize(width: 780, height: 560)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SettingsDefaults.registerOnce()
        // Touch the shared services so they initialize from the moment the app starts.
        _ = PricingService.shared
        _ = NotificationService.shared
        Task { await NotificationService.shared.requestPermissionIfNeeded() }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var bridge: StatuslineBridge
    @ObservedObject var usage: UsageStore
    @AppStorage(SettingsKey.menuBarFormat) private var formatRaw: String = MenuBarFormat.fiveHour.rawValue
    // TimelineView inside MenuBarExtra's label causes runaway CPU (rdar-worthy
    // interaction), so drive idle-flip refreshes with a plain Timer instead.
    @State private var now: Date = Date()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var format: MenuBarFormat {
        MenuBarFormat(rawValue: formatRaw) ?? .fiveHour
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
            Text(text)
        }
        .onReceive(refreshTimer) { now = $0 }
    }

    private var isFiveHourIdle: Bool {
        guard let ts = bridge.snapshot?.rateLimits?.fiveHour?.resetsAt else { return false }
        return Date(timeIntervalSince1970: ts) <= now
    }

    /// Pick a gauge variant that matches the 5-hour usage level so the icon itself
    /// gives a rough at-a-glance read even before you read the percentage.
    private var iconName: String {
        guard bridge.isFresh,
              !isFiveHourIdle,
              let pct = bridge.snapshot?.rateLimits?.fiveHour?.usedPercentage else {
            return "gauge.with.dots.needle.0percent"
        }
        switch pct {
        case ..<25:   return "gauge.with.dots.needle.0percent"
        case ..<60:   return "gauge.with.dots.needle.33percent"
        case ..<85:   return "gauge.with.dots.needle.67percent"
        default:      return "gauge.with.dots.needle.100percent"
        }
    }

    private var text: String {
        switch format {
        case .fiveHour:  return fiveHourText ?? "5h —"
        case .todayCost: return todayText    ?? "$—"
        case .both:
            let parts = [todayText, fiveHourText].compactMap { $0 }
            return parts.isEmpty ? "—" : parts.joined(separator: " · ")
        }
    }

    private var fiveHourText: String? {
        guard bridge.isFresh,
              !isFiveHourIdle,
              let pct = bridge.snapshot?.rateLimits?.fiveHour?.usedPercentage else { return nil }
        return "5h \(Int(pct.rounded()))%"
    }

    private var todayText: String? {
        let cost = usage.snapshot.today.cost
        guard cost > 0 else { return nil }
        return Fmt.dollars(cost)
    }
}
