import SwiftUI

struct RateLimitCard: View {
    let title: String
    let percentage: Double?
    let resetsAt: Date?
    let isFresh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title) {
                Text(percentageText)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isFresh ? .primary : .secondary)
            }
            ThresholdProgressBar(value: percentage ?? 0)
            resetLine
        }
    }

    @ViewBuilder
    private var resetLine: some View {
        if let resetsAt {
            HStack {
                Text("Resets in \(Fmt.duration(until: resetsAt))")
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
