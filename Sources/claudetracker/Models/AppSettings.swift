import Foundation

enum MenuBarFormat: String, CaseIterable, Identifiable {
    case fiveHour  = "fiveHour"   // "5h 33%"
    case todayCost = "todayCost"  // "$4.21"
    case both      = "both"       // "$4.21 · 5h 33%"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiveHour:  return "5-hour rate limit"
        case .todayCost: return "Today's cost"
        case .both:      return "Both"
        }
    }
}

enum SettingsKey {
    static let menuBarFormat             = "menuBarFormat"
    static let launchAtLogin             = "launchAtLogin"
    static let pricingRefreshInterval    = "pricingRefreshInterval"    // seconds; 0 = manual only

    // Notification toggles. Default to ON on first launch so permission
    // requested at startup feels motivated.
    static let notify5h80                = "notify.5h.80"
    static let notify5h95                = "notify.5h.95"
    static let notify7d80                = "notify.7d.80"
    static let notify7d95                = "notify.7d.95"

    // Per-threshold "last notified for resets_at" timestamps to dedup within a window.
    // Stored as epoch seconds; 0 = never.
    static let lastFired5h80             = "fired.5h.80.reset"
    static let lastFired5h95             = "fired.5h.95.reset"
    static let lastFired7d80             = "fired.7d.80.reset"
    static let lastFired7d95             = "fired.7d.95.reset"
}

/// Register defaults for settings that ship as ON.
enum SettingsDefaults {
    static func registerOnce() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.notify5h80: true,
            SettingsKey.notify5h95: true,
            SettingsKey.notify7d80: true,
            SettingsKey.notify7d95: true,
            SettingsKey.pricingRefreshInterval: PricingRefreshInterval.daily.rawValue,
        ])
    }
}
