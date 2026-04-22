import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var bridge: StatuslineBridge
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var sessions: SessionsBridge
    @Environment(\.openURL) private var openURL

    private var liveSessions: [LiveSession] {
        let bridgeBySession = Dictionary(
            uniqueKeysWithValues: sessions.sessions.map { ($0.sessionId, $0) }
        )
        return usage.snapshot.sessions.values
            .filter { $0.isCacheWarm }
            .map { LiveSession(state: $0, bridge: bridgeBySession[$0.sessionId]) }
            .sorted { $0.state.lastMessageAt > $1.state.lastMessageAt }
    }

    private var activeProjectNames: Set<String> {
        Set(liveSessions.map { $0.projectName })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SetupBanner()

            RateLimitCard(title: "5-HOUR BLOCK",
                          percentage: bridge.snapshot?.rateLimits?.fiveHour?.usedPercentage,
                          resetsAt: bridge.snapshot?.rateLimits?.fiveHour?.resetsAt.map { Date(timeIntervalSince1970: $0) },
                          isFresh: bridge.isFresh)
            SectionDivider()

            RateLimitCard(title: "7-DAY WINDOW",
                          percentage: bridge.snapshot?.rateLimits?.sevenDay?.usedPercentage,
                          resetsAt: bridge.snapshot?.rateLimits?.sevenDay?.resetsAt.map { Date(timeIntervalSince1970: $0) },
                          isFresh: bridge.isFresh)
            SectionDivider()

            ActiveSessionsCard(sessions: liveSessions)
            SectionDivider()

            TodayCard(bucket: usage.snapshot.today)
            SectionDivider()

            WeekCard(bucket: usage.snapshot.thisWeek)
            SectionDivider()

            ProjectBreakdownCard(
                rollups: usage.snapshot.byProject,
                activeProjects: activeProjectNames
            )
            SectionDivider()

            FooterRow()
        }
        .padding(16)
        .frame(width: 380)
    }
}

private struct FooterRow: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var bridge: StatuslineBridge
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text("Refreshed \(Fmt.relative(from: usage.snapshot.lastComputedAt, now: context.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                usage.refresh()
                bridge.reload()
            }
            .buttonStyle(.plain)
            .font(.caption)
            Text("·").foregroundStyle(.secondary)
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.plain)
            .font(.caption)
            Text("·").foregroundStyle(.secondary)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
        }
    }
}
