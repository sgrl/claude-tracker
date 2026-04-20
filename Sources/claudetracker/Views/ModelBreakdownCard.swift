import SwiftUI

struct ModelBreakdownCard: View {
    let snapshot: UsageSnapshot
    @State private var scope: Scope = .today
    @State private var expanded: Set<String> = []

    private var entries: [(key: String, bucket: Bucket)] {
        let byModel: [String: Bucket]
        switch scope {
        case .today: byModel = snapshot.byModelToday
        case .week:  byModel = snapshot.byModelWeek
        case .all:   byModel = snapshot.byModelAll
        }
        return byModel
            .map { (key: $0.key, bucket: $0.value) }
            .filter { $0.bucket.totalTokens > 0 }
            .sorted { lhs, rhs in
                if lhs.bucket.cost != rhs.bucket.cost { return lhs.bucket.cost > rhs.bucket.cost }
                return lhs.bucket.totalTokens > rhs.bucket.totalTokens
            }
    }

    private var scopeTotalCost: Double {
        snapshot.topLevelBucket(for: scope).cost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("BY MODEL") {
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if entries.isEmpty {
                Text("No activity yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(entries, id: \.key) { entry in
                        ModelRow(
                            modelId: entry.key,
                            bucket: entry.bucket,
                            totalCost: scopeTotalCost,
                            scope: scope,
                            rollups: snapshot.byProject,
                            isExpanded: expanded.contains(entry.key),
                            onToggle: { toggle(entry.key) }
                        )
                    }
                }
            }
        }
    }

    private func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) }
        else { expanded.insert(key) }
    }
}

private struct ModelRow: View {
    let modelId: String
    let bucket: Bucket
    let totalCost: Double
    let scope: Scope
    let rollups: [String: ProjectRollup]
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(displayName)
                        .font(.body.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(sharePercent)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 42, alignment: .trailing)
                    Text(Fmt.dollars(bucket.cost))
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 54, alignment: .trailing)
                    Text(Fmt.tokens(bucket.totalTokens))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 54, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ProjectsUnderModel(modelId: modelId, scope: scope, rollups: rollups)
                    .padding(.leading, 16)
                    .padding(.top, 2)
            }
        }
    }

    private var displayName: String {
        if modelId.hasPrefix("claude-") { return String(modelId.dropFirst("claude-".count)) }
        return modelId
    }

    private var sharePercent: String {
        guard totalCost > 0 else { return "—" }
        let share = (bucket.cost / totalCost) * 100
        return "\(Int(share.rounded()))%"
    }
}

private struct ProjectsUnderModel: View {
    let modelId: String
    let scope: Scope
    let rollups: [String: ProjectRollup]

    private var rows: [(key: String, bucket: Bucket)] {
        rollups.compactMap { key, rollup -> (String, Bucket)? in
            guard let b = rollup.byModel(for: scope)[modelId], b.totalTokens > 0 else { return nil }
            return (key, b)
        }
        .sorted { $0.1.cost > $1.1.cost }
    }

    var body: some View {
        if rows.isEmpty {
            Text("No project breakdown available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows, id: \.key) { row in
                    HStack {
                        Text(row.key)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Fmt.dollars(row.bucket.cost))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 54, alignment: .trailing)
                        Text(Fmt.tokens(row.bucket.totalTokens))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 54, alignment: .trailing)
                    }
                }
            }
        }
    }
}
