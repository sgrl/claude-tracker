import SwiftUI
import AppKit

/// A single live session as displayed in the Active Sessions card. Combines the
/// JSONL-derived cache state with bridge-file metadata when the session still
/// has a bridge file on disk (authoritative cost, ctx %, etc.).
struct LiveSession: Identifiable, Equatable {
    let state: SessionCacheState
    let bridge: SessionState?

    var id: String { state.sessionId }

    var projectName: String {
        if let cwd = state.cwd, let last = cwd.split(separator: "/").last {
            return String(last)
        }
        return state.projectKey
    }

    var displayModel: String {
        if let b = bridge { return b.shortModelName }
        let id = state.modelId
        return id.hasPrefix("claude-") ? String(id.dropFirst("claude-".count)) : id
    }

    var costUSD: Double? {
        if let b = bridge?.cost?.totalCostUsd { return b }
        return state.bucket.cost > 0 ? state.bucket.cost : nil
    }

    var contextPct: Double? { bridge?.contextWindow?.usedPercentage }

    var linesSummary: String? {
        let added = bridge?.cost?.totalLinesAdded ?? 0
        let removed = bridge?.cost?.totalLinesRemoved ?? 0
        if added == 0 && removed == 0 { return nil }
        return "+\(added)/-\(removed)"
    }

    var transcriptPath: String? {
        if let b = bridge?.transcriptPath { return b }
        return state.transcriptURL?.path
    }
}

struct ActiveSessionsCard: View {
    let sessions: [LiveSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("ACTIVE SESSIONS") {
                Text("\(sessions.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if sessions.isEmpty {
                Text("No warm-cache sessions right now.")
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
    let session: LiveSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(action: openDetail) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(session.projectName)
                        .font(.body.monospacedDigit())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let cost = session.costUSD {
                        Text(Fmt.dollars(cost))
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(session.displayModel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let pct = session.contextPct {
                        bullet
                        Text("ctx \(Int(pct.rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let lines = session.linesSummary {
                        bullet
                        Text(lines)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    CacheStatusBadge(state: session.state)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bullet: some View {
        Text("·").foregroundStyle(.secondary)
    }

    private func openDetail() {
        guard let path = session.transcriptPath else { return }
        let target = SessionDetailTarget(
            sessionId: session.state.sessionId,
            transcriptPath: path,
            projectName: session.projectName,
            cwd: session.state.cwd
        )
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "session-detail", value: target)
    }
}

private struct CacheStatusBadge: View {
    let state: SessionCacheState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
            Text(text)
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(tint)
    }

    private var text: String {
        let remaining = state.cacheTimeRemaining
        if let win = state.dominantWindow {
            return "\(win.label) ▸ \(Fmt.shortRemaining(remaining))"
        }
        // No cache written yet — show the warmup allowance countdown.
        return "warmup \(Fmt.shortRemaining(remaining))"
    }

    private var tint: Color {
        let remaining = state.cacheTimeRemaining
        if remaining < 60 { return .orange }
        return .green
    }
}
