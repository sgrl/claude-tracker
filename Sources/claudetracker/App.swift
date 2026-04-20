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
            MenuBarLabel(bridge: bridge)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var bridge: StatuslineBridge

    var body: some View {
        if let pct = bridge.snapshot?.rateLimits?.fiveHour?.usedPercentage, bridge.isFresh {
            Text("5h \(Int(pct.rounded()))%")
        } else {
            Text("5h —")
        }
    }
}
