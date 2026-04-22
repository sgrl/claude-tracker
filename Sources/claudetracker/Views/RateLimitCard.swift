import SwiftUI

struct RateLimitCard: View {
    let title: String
    let percentage: Double?
    let resetsAt: Date?
    let isFresh: Bool

    var body: some View {
        // Wrap the whole card so "idle" transitions (resetsAt crossing into the
        // past) happen live without needing a new statusline payload to arrive.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let idle = isIdle(at: context.date)
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title) {
                    Text(idle ? "—" : percentageText)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(isFresh && !idle ? .primary : .secondary)
                }
                ThresholdProgressBar(value: idle ? 0 : (percentage ?? 0))
                resetLine(now: context.date, idle: idle)
            }
        }
    }

    private func isIdle(at now: Date) -> Bool {
        if let resetsAt { return resetsAt <= now }
        return false
    }

    @ViewBuilder
    private func resetLine(now: Date, idle: Bool) -> some View {
        if idle {
            Text("Idle — waiting for next Claude Code session…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let resetsAt {
            HStack {
                Text("Resets in \(Fmt.duration(from: now, until: resetsAt))")
                    .font(.caption.monospacedDigit())
                Spacer()
                Text(Fmt.dayTime(resetsAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if percentage != nil {
            Text("Reset time unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(isFresh ? "No data yet" : "Waiting for next Claude Code session…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentageText: String {
        if let p = percentage { return Fmt.percent(p) }
        return "—"
    }
}
