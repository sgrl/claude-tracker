import SwiftUI
import AppKit

@main
struct ClaudeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bridge = StatuslineBridge()
    @StateObject private var usage = UsageStore()
    @StateObject private var sessions = SessionsBridge()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(bridge)
                .environmentObject(usage)
                .environmentObject(sessions)
        } label: {
            MenuBarLabel(bridge: bridge, usage: usage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Touch the shared PricingService so it loads its cache and schedules
        // auto-refresh from the moment the app starts.
        _ = PricingService.shared
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var bridge: StatuslineBridge
    @ObservedObject var usage: UsageStore
    @AppStorage(SettingsKey.menuBarFormat) private var formatRaw: String = MenuBarFormat.fiveHour.rawValue

    private var format: MenuBarFormat {
        MenuBarFormat(rawValue: formatRaw) ?? .fiveHour
    }

    var body: some View {
        Text(text)
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
              let pct = bridge.snapshot?.rateLimits?.fiveHour?.usedPercentage else { return nil }
        return "5h \(Int(pct.rounded()))%"
    }

    private var todayText: String? {
        let cost = usage.snapshot.today.cost
        guard cost > 0 else { return nil }
        return Fmt.dollars(cost)
    }
}
