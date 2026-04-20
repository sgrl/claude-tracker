import Foundation

enum Fmt {
    static func dollars(_ v: Double) -> String {
        if v >= 100 { return String(format: "$%.0f", v) }
        if v >= 10  { return String(format: "$%.1f", v) }
        return String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000     { return String(format: "%.0fk", d / 1_000) }
        return "\(n)"
    }

    static func percent(_ v: Double) -> String {
        "\(Int(v.rounded()))%"
    }

    static func duration(until date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSinceNow))
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func dayTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM · HH:mm"
        return df.string(from: date)
    }

    static func shortTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.timeStyle = .short
        return df.string(from: date)
    }

    static func relative(from date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 5     { return "just now" }
        if secs < 60    { return "\(secs)s ago" }
        if secs < 3600  { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }
}
