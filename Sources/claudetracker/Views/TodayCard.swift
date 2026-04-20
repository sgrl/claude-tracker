import SwiftUI

struct TodayCard: View {
    let bucket: Bucket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TODAY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(costLabel)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                Text("·").foregroundStyle(.secondary)
                Text("\(Fmt.tokens(bucket.totalTokens)) tokens")
                    .font(.body.monospacedDigit())
                Text("·").foregroundStyle(.secondary)
                Text("\(bucket.sessionIds.count) session\(bucket.sessionIds.count == 1 ? "" : "s")")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label("in \(Fmt.tokens(bucket.inputTokens))", systemImage: "arrow.down")
                Label("out \(Fmt.tokens(bucket.outputTokens))", systemImage: "arrow.up")
                Label("cache-r \(Fmt.tokens(bucket.cacheReadTokens))", systemImage: "bolt")
                Label("cache-w \(Fmt.tokens(bucket.cacheWriteTokens))", systemImage: "square.and.arrow.down")
            }
            .labelStyle(.titleAndIcon)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var costLabel: String {
        let base = "\(Fmt.dollars(bucket.cost)) est"
        return bucket.hasUnknownPricing ? "\(base) +" : base
    }
}
