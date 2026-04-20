import SwiftUI

struct RateLimitCard: View {
    let title: String
    let percentage: Double?
    let resetsAt: Date?
    let isFresh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentageText)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isFresh ? .primary : .secondary)
            }
            ProgressView(value: (percentage ?? 0) / 100.0)
                .progressViewStyle(.linear)
                .tint(barTint)
            if let resetsAt {
                HStack {
                    Text("Resets in \(Fmt.duration(until: resetsAt))")
                        .font(.caption)
                    Spacer()
                    Text(Fmt.dayTime(resetsAt))
                        .font(.caption)
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
    }

    private var percentageText: String {
        if let p = percentage { return Fmt.percent(p) }
        return "—"
    }

    private var barTint: Color {
        guard let p = percentage else { return .secondary }
        switch p {
        case ..<50:  return .green
        case ..<80:  return .yellow
        default:     return .red
        }
    }
}
