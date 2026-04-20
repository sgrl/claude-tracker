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
}
