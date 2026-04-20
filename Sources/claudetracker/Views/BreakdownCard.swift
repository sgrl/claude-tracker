import SwiftUI

struct BreakdownCard: View {
    let title: String
    let entries: [(key: String, bucket: Bucket)]

    private var sorted: [(key: String, bucket: Bucket)] {
        entries.sorted { lhs, rhs in
            if lhs.bucket.cost != rhs.bucket.cost { return lhs.bucket.cost > rhs.bucket.cost }
            return lhs.bucket.totalTokens > rhs.bucket.totalTokens
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if sorted.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sorted.prefix(5), id: \.key) { row in
                    HStack {
                        Text(displayKey(row.key))
                            .font(.body.monospacedDigit())
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(Fmt.dollars(row.bucket.cost))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.primary)
                            .frame(minWidth: 54, alignment: .trailing)
                        Text(Fmt.tokens(row.bucket.totalTokens))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 54, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func displayKey(_ key: String) -> String {
        // Strip leading "claude-" from model ids to save space.
        if key.hasPrefix("claude-") { return String(key.dropFirst("claude-".count)) }
        return key
    }
}
