import SwiftUI
import AppKit

struct ActiveSessionsCard: View {
    let sessions: [SessionState]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("ACTIVE SESSIONS") {
                Text("\(sessions.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if sessions.isEmpty {
                Text("No sessions pinged in the last 10 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(sessions) { s in
                        SessionRow(session: s)
                    }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: openDetail) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(session.projectName)
                        .font(.body.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let cost = session.cost?.totalCostUsd {
                        Text(Fmt.dollars(cost))
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(session.shortModelName)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let pct = session.contextWindow?.usedPercentage {
                        Text("·").foregroundStyle(.secondary)
                        Text("ctx \(Int(pct.rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let lines = totalLines(for: session) {
                        Text("·").foregroundStyle(.secondary)
                        Text(lines)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let t = session.lastPingAt {
                        Text(Fmt.relative(from: t))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openDetail() {
        guard let path = session.transcriptPath else { return }
        let target = SessionDetailTarget(
            sessionId: session.sessionId,
            transcriptPath: path,
            projectName: session.projectName,
            cwd: session.cwd
        )
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "session-detail", value: target)
    }

    private func totalLines(for session: SessionState) -> String? {
        let added = session.cost?.totalLinesAdded ?? 0
        let removed = session.cost?.totalLinesRemoved ?? 0
        if added == 0 && removed == 0 { return nil }
        return "+\(added)/-\(removed)"
    }
}
