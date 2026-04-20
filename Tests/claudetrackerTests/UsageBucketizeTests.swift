import XCTest
@testable import claudetracker

final class UsageBucketizeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Pricing.setLive([:])
    }

    private func entry(
        ts: Date,
        sessionId: String = "sess-1",
        messageId: String,
        modelId: String = "claude-opus-4-7",
        projectKey: String = "proj-a",
        input: Int = 1_000,
        output: Int = 1_000,
        cacheWrite: Int = 0,
        cacheRead: Int = 0,
        ephem5m: Int = 0,
        ephem1h: Int = 0
    ) -> UsageEntry {
        UsageEntry(
            timestamp: ts,
            modelId: modelId,
            projectKey: projectKey,
            cwd: "/tmp/\(projectKey)",
            sessionId: sessionId,
            messageId: messageId,
            inputTokens: input,
            outputTokens: output,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            ephemeral5mWriteTokens: ephem5m,
            ephemeral1hWriteTokens: ephem1h
        )
    }

    private func fileState(_ entries: [UsageEntry], url: URL = URL(fileURLWithPath: "/tmp/a.jsonl")) -> FileParseState {
        FileParseState(url: url, size: 0, mtime: Date(), nextOffset: 0, entries: entries)
    }

    func testDedupAcrossFiles() {
        // Same messageId appearing in two files is counted once.
        let now = Date()
        let e = entry(ts: now, messageId: "msg-1", input: 1_000, output: 2_000)
        let a = fileState([e], url: URL(fileURLWithPath: "/tmp/a.jsonl"))
        let b = fileState([e], url: URL(fileURLWithPath: "/tmp/b.jsonl"))
        let snap = UsageStore.bucketize(fileStates: [a.url: a, b.url: b])
        XCTAssertEqual(snap.entryCount, 1)
        XCTAssertEqual(snap.today.inputTokens, 1_000)
        XCTAssertEqual(snap.today.outputTokens, 2_000)
    }

    func testTodayWeekAllTimeBuckets() {
        let now = Date()
        let cal = Calendar.current
        let aWeekAgo  = cal.date(byAdding: .day, value: -8, to: now)!
        let threeDays = cal.date(byAdding: .day, value: -3, to: now)!
        let today     = cal.date(byAdding: .hour, value: -1, to: now)!

        let e1 = entry(ts: aWeekAgo, messageId: "old",   input: 1_000_000)
        let e2 = entry(ts: threeDays, messageId: "mid",  input: 1_000_000)
        let e3 = entry(ts: today,     messageId: "new",  input: 1_000_000)

        let s = fileState([e1, e2, e3])
        let snap = UsageStore.bucketize(fileStates: [s.url: s])

        XCTAssertEqual(snap.today.inputTokens,   1_000_000)
        XCTAssertEqual(snap.thisWeek.inputTokens, 2_000_000)
        XCTAssertEqual(snap.allTime.inputTokens,  3_000_000)
    }

    func testDailyLast7PopulatedChronologically() {
        let now = Date()
        let cal = Calendar.current
        var entries: [UsageEntry] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: -i, to: now)!
            entries.append(entry(ts: d, messageId: "m-\(i)", input: Int(100 + i * 10)))
        }
        let s = fileState(entries)
        let snap = UsageStore.bucketize(fileStates: [s.url: s])
        XCTAssertEqual(snap.dailyLast7.count, 7)
        // Oldest-first ordering.
        for i in 1..<snap.dailyLast7.count {
            XCTAssertLessThan(snap.dailyLast7[i-1].day, snap.dailyLast7[i].day)
        }
    }

    func testSessionCacheStateCapturesLatestWrites() {
        let now = Date()
        let cal = Calendar.current
        let t0 = cal.date(byAdding: .minute, value: -40, to: now)!
        let t1 = cal.date(byAdding: .minute, value: -20, to: now)!
        let t2 = cal.date(byAdding: .minute, value: -2,  to: now)!

        let e1 = entry(ts: t0, messageId: "m1", ephem5m: 100)       // 5m write, old
        let e2 = entry(ts: t1, messageId: "m2", ephem1h: 100)       // 1h write 20m ago
        let e3 = entry(ts: t2, messageId: "m3", ephem5m: 100)       // 5m write 2m ago (dominant)

        let s = fileState([e1, e2, e3])
        let snap = UsageStore.bucketize(fileStates: [s.url: s])
        let state = snap.sessions["sess-1"]
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.last5mWriteAt, t2)
        XCTAssertEqual(state?.last1hWriteAt, t1)
        // 5m + 5min = ~3 min from now; 1h + 1h = ~40 min from now. Later wins → cache warmth anchored on 1h.
        XCTAssertEqual(state?.dominantWindow, .oneHour)
        XCTAssertTrue(state?.isCacheWarm ?? false)
    }

    func testSessionBecomesColdAfterAllWritesExpire() {
        let cal = Calendar.current
        let longAgo = cal.date(byAdding: .hour, value: -2, to: Date())!  // past 1h TTL
        let veryLongAgo = cal.date(byAdding: .hour, value: -3, to: Date())!

        let e1 = entry(ts: veryLongAgo, messageId: "m1", ephem5m: 100)
        let e2 = entry(ts: longAgo,     messageId: "m2", ephem1h: 100)

        let s = fileState([e1, e2])
        let snap = UsageStore.bucketize(fileStates: [s.url: s])
        let state = snap.sessions["sess-1"]
        XCTAssertNotNil(state)
        XCTAssertFalse(state?.isCacheWarm ?? true)
    }

    func testByProjectRollupsPerScope() {
        let now = Date()
        let cal = Calendar.current
        let older = cal.date(byAdding: .day, value: -3, to: now)!

        let proj1a = entry(ts: now,   messageId: "p1a", projectKey: "alpha", input: 1_000_000)
        let proj1b = entry(ts: older, messageId: "p1b", projectKey: "alpha", input: 2_000_000)
        let proj2  = entry(ts: now,   messageId: "p2",  projectKey: "beta",  input: 500_000)

        let s = fileState([proj1a, proj1b, proj2])
        let snap = UsageStore.bucketize(fileStates: [s.url: s])

        let alpha = snap.byProject["alpha"]
        XCTAssertNotNil(alpha)
        XCTAssertEqual(alpha?.today.inputTokens, 1_000_000)
        XCTAssertEqual(alpha?.week.inputTokens,  3_000_000)
        XCTAssertEqual(alpha?.allTime.inputTokens, 3_000_000)

        XCTAssertEqual(snap.byProject["beta"]?.today.inputTokens, 500_000)
    }
}
