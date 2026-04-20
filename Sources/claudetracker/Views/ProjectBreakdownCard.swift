import SwiftUI

struct ProjectBreakdownCard: View {
    let rollups: [String: ProjectRollup]
    let activeProjects: Set<String>
    @State private var scope: Scope = .today
    @State private var expanded: Set<String> = []

    private var sorted: [(key: String, rollup: ProjectRollup)] {
        rollups.map { (key: $0.key, rollup: $0.value) }
            .filter { $0.rollup.bucket(for: scope).totalTokens > 0 }
            .sorted { lhs, rhs in
                let lb = lhs.rollup.bucket(for: scope)
                let rb = rhs.rollup.bucket(for: scope)
                if lb.cost != rb.cost { return lb.cost > rb.cost }
                return lb.totalTokens > rb.totalTokens
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("BY PROJECT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if sorted.isEmpty {
                Text("No activity yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(sorted, id: \.key) { entry in
                        ProjectRow(
                            name: entry.key,
                            rollup: entry.rollup,
                            scope: scope,
                            isActive: activeProjects.contains(entry.key),
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

private struct ProjectRow: View {
    let name: String
    let rollup: ProjectRollup
    let scope: Scope
    let isActive: Bool
    let isExpanded: Bool
    let onToggle: () -> Void

    private var bucket: Bucket { rollup.bucket(for: scope) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    } else {
                        Color.clear.frame(width: 6, height: 6)
                    }
                    Text(name)
                        .font(.body.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
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
                ProjectDetail(rollup: rollup, scope: scope)
                    .padding(.leading, 22)
                    .padding(.top, 2)
            }
        }
    }
}

private struct ProjectDetail: View {
    let rollup: ProjectRollup
    let scope: Scope

    private var modelRows: [(key: String, bucket: Bucket)] {
        rollup.byModel(for: scope)
            .map { (key: $0.key, bucket: $0.value) }
            .sorted { $0.bucket.cost > $1.bucket.cost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(modelRows, id: \.key) { row in
                HStack {
                    Text(shortModel(row.key))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
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
            let b = rollup.bucket(for: scope)
            HStack(spacing: 10) {
                Text("\(b.sessionIds.count) session\(b.sessionIds.count == 1 ? "" : "s")")
                if let last = rollup.lastActivityAt {
                    Text("·")
                    Text("last \(Fmt.relative(from: last))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private func shortModel(_ id: String) -> String {
        if id.hasPrefix("claude-") { return String(id.dropFirst("claude-".count)) }
        return id
    }
}
