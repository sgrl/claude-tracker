import SwiftUI

struct WeekCard: View {
    let bucket: Bucket

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("THIS WEEK")
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
        }
    }

    private var costLabel: String {
        let base = "\(Fmt.dollars(bucket.cost)) est"
        return bucket.hasUnknownPricing ? "\(base) +" : base
    }
}
