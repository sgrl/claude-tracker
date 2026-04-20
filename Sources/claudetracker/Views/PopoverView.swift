import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var bridge: StatuslineBridge
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var sessions: SessionsBridge
    @State private var tick: Int = 0
    @Environment(\.openURL) private var openURL

    private let tickTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActiveSessionsCard(sessions: sessions.activeSessions)
            SectionDivider()

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

            TodayCard(bucket: usage.snapshot.today)
            SectionDivider()

            WeekCard(bucket: usage.snapshot.thisWeek, dailyLast7: usage.snapshot.dailyLast7)
            SectionDivider()

            BreakdownCard(title: "BY MODEL (today)",
                          entries: usage.snapshot.byModelToday.map { (key: $0.key, bucket: $0.value) })
            SectionDivider()

            ProjectBreakdownCard(
                rollups: usage.snapshot.byProject,
                activeProjects: Set(sessions.activeSessions.map(\.projectName))
            )
            SectionDivider()

            FooterRow()
        }
        .padding(16)
        .frame(width: 380)
        .onReceive(tickTimer) { _ in tick &+= 1 }
        .id(tick) // re-render so "in 2h 14m" counters stay live
    }
}

private struct FooterRow: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var bridge: StatuslineBridge

    var body: some View {
        HStack {
            Text("Refreshed \(Fmt.relative(from: usage.snapshot.lastComputedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") {
                usage.refresh()
                bridge.reload()
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
