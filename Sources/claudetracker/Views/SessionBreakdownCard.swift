import SwiftUI
import AppKit

struct SessionBreakdownCard: View {
    let sessions: [SessionCacheState]
    let activeSessionIds: Set<String>
    @State private var scope: Scope = .today
    @State private var expanded: Bool = false

    private let cal = Calendar.current

    private var filtered: [SessionCacheState] {
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfWeek = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        return sessions.filter { s in
            switch scope {
            case .today: return s.lastMessageAt >= startOfToday
            case .week:  return s.lastMessageAt >= startOfWeek
            case .all:   return true
            }
        }
        .sorted { $0.bucket.cost > $1.bucket.cost }
    }

    private let collapsedLimit = 5
    private let expandedLimit = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("SESSIONS") {
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if filtered.isEmpty {
                Text("No sessions in this range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 3) {
                    let limit = expanded ? expandedLimit : collapsedLimit
                    ForEach(filtered.prefix(limit)) { s in
                        SessionRow(
                            session: s,
                            isActive: activeSessionIds.contains(s.sessionId)
                        )
                    }
                    if filtered.count > collapsedLimit {
                        Button(action: { expanded.toggle() }) {
                            HStack {
                                Text(expanded
                                     ? "Show fewer"
                                     : "Show \(min(filtered.count, expandedLimit) - collapsedLimit) more")
                                    .font(.caption)
                                Spacer()
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionCacheState
    let isActive: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: openDetail) {
            HStack(spacing: 6) {
                if isActive {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(projectName)
                        .font(.body.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(shortModel)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                        Text(Fmt.relative(from: session.lastMessageAt))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(Fmt.dollars(session.bucket.cost))
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 54, alignment: .trailing)
                Text(Fmt.tokens(session.bucket.totalTokens))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 54, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var projectName: String {
        if let cwd = session.cwd, let last = cwd.split(separator: "/").last {
            return String(last)
        }
        return session.projectKey
    }

    private var shortModel: String {
        let id = session.modelId
        return id.hasPrefix("claude-") ? String(id.dropFirst("claude-".count)) : id
    }

    private func openDetail() {
        guard let url = session.transcriptURL else { return }
        let target = SessionDetailTarget(
            sessionId: session.sessionId,
            transcriptPath: url.path,
            projectName: projectName,
            cwd: session.cwd
        )
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "session-detail", value: target)
    }
}
