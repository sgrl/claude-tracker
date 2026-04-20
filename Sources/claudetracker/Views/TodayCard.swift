import SwiftUI

struct TodayCard: View {
    let bucket: Bucket

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("TODAY") {
                LeadAmount(amount: bucket.cost, approximate: bucket.hasUnknownPricing)
            }
            HStack(spacing: 8) {
                Text("\(Fmt.tokens(bucket.totalTokens)) tokens")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text("\(bucket.sessionIds.count) session\(bucket.sessionIds.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TokenBreakdownRow(bucket: bucket)
        }
    }
}

struct TokenBreakdownRow: View {
    let bucket: Bucket

    var body: some View {
        HStack(spacing: 12) {
            tokenCell(label: "in",      value: bucket.inputTokens)
            tokenCell(label: "out",     value: bucket.outputTokens)
            tokenCell(label: "cache-r", value: bucket.cacheReadTokens)
            tokenCell(label: "cache-w", value: bucket.cacheWriteTokens)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func tokenCell(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
            Text(Fmt.tokens(value))
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}
