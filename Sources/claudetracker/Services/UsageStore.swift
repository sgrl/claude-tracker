import Foundation
import Combine

/// Parser-side state for a single JSONL file. Kept so we only re-read bytes past
/// `nextOffset` on subsequent refreshes.
struct FileParseState: Equatable {
    let url: URL
    var size: Int
    var mtime: Date
    var nextOffset: Int         // byte offset where next read starts (always at a line boundary)
    var entries: [UsageEntry]   // parsed entries for this file, in order
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .init()
    @Published private(set) var isRefreshing: Bool = false

    private let projectsDir: URL = URL(fileURLWithPath:
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects"))

    private var fileStates: [URL: FileParseState] = [:]
    private var refreshTimer: Timer?
    private var fsSource: DispatchSourceFileSystemObject?
    private var fsFd: Int32 = -1
    private var pricingObserver: NSObjectProtocol?

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        attachDirWatcher()
        pricingObserver = NotificationCenter.default.addObserver(
            forName: .pricingDidUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebucket() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        fsSource?.cancel()
        if fsFd >= 0 { close(fsFd) }
        if let obs = pricingObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let dir = projectsDir
        let currentStates = fileStates
        Task.detached(priority: .utility) {
            let (newStates, snap) = UsageStore.computeIncremental(
                projectsDir: dir, existing: currentStates
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.fileStates = newStates
                self.snapshot = snap
                self.isRefreshing = false
            }
        }
    }

    /// Re-bucket from existing parsed entries without re-reading files. Used when
    /// prices change — cost-per-entry shifts but entries themselves don't.
    private func rebucket() {
        let states = fileStates
        Task.detached(priority: .utility) {
            let snap = UsageStore.bucketize(fileStates: states)
            await MainActor.run { [weak self] in
                self?.snapshot = snap
            }
        }
    }

    // MARK: - Pure compute (nonisolated)

    nonisolated private static func computeIncremental(
        projectsDir: URL,
        existing: [URL: FileParseState]
    ) -> ([URL: FileParseState], UsageSnapshot) {
        var states = existing
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (states, UsageSnapshot())
        }

        var seenOnDisk = Set<URL>()

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            seenOnDisk.insert(url)

            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            let mtime = values?.contentModificationDate ?? .distantPast

            if let cached = states[url] {
                if cached.size == size && cached.mtime == mtime {
                    continue                                    // unchanged — keep state as-is
                }
                if size < cached.size {
                    // File shrunk — likely a rewrite; re-read from scratch.
                    states[url] = parseFull(url: url, size: size, mtime: mtime)
                } else {
                    states[url] = extendParse(prior: cached, url: url, size: size, mtime: mtime)
                }
            } else {
                states[url] = parseFull(url: url, size: size, mtime: mtime)
            }
        }

        // Drop cache entries for files that disappeared.
        for key in states.keys where !seenOnDisk.contains(key) {
            states.removeValue(forKey: key)
        }

        let snap = bucketize(fileStates: states)
        return (states, snap)
    }

    nonisolated private static func parseFull(url: URL, size: Int, mtime: Date) -> FileParseState {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return FileParseState(url: url, size: 0, mtime: mtime, nextOffset: 0, entries: [])
        }
        let projectKey = projectKey(forProjectDir: url.deletingLastPathComponent())
        let (entries, lastBoundary) = parseRange(data: data, from: 0, projectKey: projectKey)
        return FileParseState(url: url, size: size, mtime: mtime, nextOffset: lastBoundary, entries: entries)
    }

    nonisolated private static func extendParse(
        prior: FileParseState,
        url: URL,
        size: Int,
        mtime: Date
    ) -> FileParseState {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return prior
        }
        let projectKey = projectKey(forProjectDir: url.deletingLastPathComponent())
        let (newEntries, lastBoundary) = parseRange(
            data: data, from: prior.nextOffset, projectKey: projectKey
        )
        var merged = prior.entries
        merged.append(contentsOf: newEntries)
        return FileParseState(
            url: url,
            size: size,
            mtime: mtime,
            nextOffset: lastBoundary,
            entries: merged
        )
    }

    /// Parse the given data starting at `from`. Returns the entries found plus the
    /// offset of the byte *after* the last newline that was consumed (so a later call
    /// can resume from there without re-parsing partial tail lines).
    nonisolated private static func parseRange(
        data: Data,
        from start: Int,
        projectKey: String
    ) -> ([UsageEntry], Int) {
        guard start < data.count else { return ([], data.count) }
        var entries: [UsageEntry] = []
        var lastBoundary = start

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var lineStart = start
            for i in start..<data.count {
                let byte = base.load(fromByteOffset: i, as: UInt8.self)
                if byte == 0x0A { // '\n'
                    if i > lineStart {
                        let lineData = Data(
                            bytesNoCopy: UnsafeMutableRawPointer(mutating: base.advanced(by: lineStart)),
                            count: i - lineStart,
                            deallocator: .none
                        )
                        if let e = decodeEntry(
                            lineData,
                            projectKey: projectKey,
                            formatter: formatter,
                            formatterNoFrac: formatterNoFrac
                        ) {
                            entries.append(e)
                        }
                    }
                    lineStart = i + 1
                    lastBoundary = i + 1
                }
            }
        }
        return (entries, lastBoundary)
    }

    nonisolated private static func decodeEntry(
        _ data: Data,
        projectKey fallbackProjectKey: String,
        formatter: ISO8601DateFormatter,
        formatterNoFrac: ISO8601DateFormatter
    ) -> UsageEntry? {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              (raw["type"] as? String) == "assistant",
              let message = raw["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let messageId = message["id"] as? String,
              let timestampStr = raw["timestamp"] as? String else {
            return nil
        }
        let ts = formatter.date(from: timestampStr) ?? formatterNoFrac.date(from: timestampStr)
        guard let ts else { return nil }

        let modelId  = (message["model"] as? String) ?? "unknown"
        let sessionId = (raw["sessionId"] as? String) ?? ""
        let cwd = raw["cwd"] as? String
        let projectKey: String = {
            if let cwd, let last = cwd.split(separator: "/").last {
                return String(last)
            }
            return fallbackProjectKey
        }()

        // Cache-creation breakdown lets us tell 5-minute writes apart from 1-hour
        // writes, which determines how long the session's cache stays warm.
        let cacheCreation = usage["cache_creation"] as? [String: Any]
        let ephem5m = (cacheCreation?["ephemeral_5m_input_tokens"] as? Int) ?? 0
        let ephem1h = (cacheCreation?["ephemeral_1h_input_tokens"] as? Int) ?? 0

        let entry = UsageEntry(
            timestamp: ts,
            modelId: modelId,
            projectKey: projectKey,
            cwd: cwd,
            sessionId: sessionId,
            messageId: messageId,
            inputTokens:      (usage["input_tokens"] as? Int) ?? 0,
            outputTokens:     (usage["output_tokens"] as? Int) ?? 0,
            cacheWriteTokens: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
            cacheReadTokens:  (usage["cache_read_input_tokens"]  as? Int) ?? 0,
            ephemeral5mWriteTokens: ephem5m,
            ephemeral1hWriteTokens: ephem1h
        )
        return entry.totalTokens == 0 ? nil : entry
    }

    /// Bucket the cached entries into today / week / all + per-project / per-model rollups.
    /// Global dedup by messageId across files (same id can appear in multiple JSONL files).
    nonisolated static func bucketize(fileStates: [URL: FileParseState]) -> UsageSnapshot {
        var snap = UsageSnapshot()

        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfWeek  = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        var dailyBuckets: [Date: Bucket] = [:]
        for i in 0..<7 {
            if let d = cal.date(byAdding: .day, value: -i, to: startOfToday) {
                dailyBuckets[d] = Bucket()
            }
        }

        var seenMessageIds = Set<String>()
        var entryCount = 0

        // Per-session scratchpads so we can emit SessionCacheState at the end.
        struct SessionAcc {
            var cwd: String?
            var projectKey: String
            var modelId: String
            var firstMessageAt: Date
            var lastMessageAt: Date
            var last5mWriteAt: Date?
            var last1hWriteAt: Date?
            var transcriptURL: URL?
            var bucket: Bucket
        }
        var sessions: [String: SessionAcc] = [:]

        // Merge in deterministic order so dedup wins stay stable across runs.
        let ordered = fileStates.keys.sorted { $0.path < $1.path }
        for key in ordered {
            guard let state = fileStates[key] else { continue }
            let fileURL = state.url
            for entry in state.entries {
                if seenMessageIds.contains(entry.messageId) { continue }
                seenMessageIds.insert(entry.messageId)
                entryCount += 1
                ingest(
                    entry: entry,
                    cal: cal,
                    startOfToday: startOfToday,
                    startOfWeek: startOfWeek,
                    dailyBuckets: &dailyBuckets,
                    snap: &snap
                )

                if !entry.sessionId.isEmpty {
                    var acc = sessions[entry.sessionId] ?? SessionAcc(
                        cwd: entry.cwd,
                        projectKey: entry.projectKey,
                        modelId: entry.modelId,
                        firstMessageAt: entry.timestamp,
                        lastMessageAt: entry.timestamp,
                        last5mWriteAt: nil,
                        last1hWriteAt: nil,
                        transcriptURL: fileURL,
                        bucket: .init()
                    )
                    if entry.timestamp < acc.firstMessageAt { acc.firstMessageAt = entry.timestamp }
                    if entry.timestamp > acc.lastMessageAt {
                        acc.lastMessageAt = entry.timestamp
                        acc.modelId = entry.modelId
                        if entry.cwd != nil { acc.cwd = entry.cwd }
                    }
                    if entry.ephemeral5mWriteTokens > 0 {
                        if acc.last5mWriteAt == nil || entry.timestamp > acc.last5mWriteAt! {
                            acc.last5mWriteAt = entry.timestamp
                        }
                    }
                    if entry.ephemeral1hWriteTokens > 0 {
                        if acc.last1hWriteAt == nil || entry.timestamp > acc.last1hWriteAt! {
                            acc.last1hWriteAt = entry.timestamp
                        }
                    }
                    acc.bucket.add(entry)
                    acc.transcriptURL = fileURL
                    sessions[entry.sessionId] = acc
                }
            }
        }

        var sessionStates: [String: SessionCacheState] = [:]
        for (sid, acc) in sessions {
            sessionStates[sid] = SessionCacheState(
                sessionId: sid,
                cwd: acc.cwd,
                projectKey: acc.projectKey,
                modelId: acc.modelId,
                firstMessageAt: acc.firstMessageAt,
                lastMessageAt: acc.lastMessageAt,
                last5mWriteAt: acc.last5mWriteAt,
                last1hWriteAt: acc.last1hWriteAt,
                transcriptURL: acc.transcriptURL,
                bucket: acc.bucket
            )
        }

        snap.sessions = sessionStates
        snap.entryCount = entryCount
        snap.dailyLast7 = dailyBuckets
            .map { DailyBucket(day: $0.key, bucket: $0.value) }
            .sorted { $0.day < $1.day }
        snap.lastComputedAt = Date()
        return snap
    }

    nonisolated private static func ingest(
        entry: UsageEntry,
        cal: Calendar,
        startOfToday: Date,
        startOfWeek: Date,
        dailyBuckets: inout [Date: Bucket],
        snap: inout UsageSnapshot
    ) {
        var rollup = snap.byProject[entry.projectKey] ?? ProjectRollup()

        if entry.timestamp >= startOfToday {
            snap.today.add(entry)
            snap.byModelToday[entry.modelId, default: .init()].add(entry)
            rollup.today.add(entry)
            rollup.byModelToday[entry.modelId, default: .init()].add(entry)
        }
        if entry.timestamp >= startOfWeek {
            snap.thisWeek.add(entry)
            snap.byModelWeek[entry.modelId, default: .init()].add(entry)
            rollup.week.add(entry)
            rollup.byModelWeek[entry.modelId, default: .init()].add(entry)
            let dayStart = cal.startOfDay(for: entry.timestamp)
            if var b = dailyBuckets[dayStart] {
                b.add(entry)
                dailyBuckets[dayStart] = b
            }
        }
        snap.allTime.add(entry)
        snap.byModelAll[entry.modelId, default: .init()].add(entry)
        rollup.allTime.add(entry)
        rollup.byModelAll[entry.modelId, default: .init()].add(entry)

        if rollup.firstActivityAt == nil || entry.timestamp < rollup.firstActivityAt! {
            rollup.firstActivityAt = entry.timestamp
        }
        if rollup.lastActivityAt == nil || entry.timestamp > rollup.lastActivityAt! {
            rollup.lastActivityAt = entry.timestamp
        }
        snap.byProject[entry.projectKey] = rollup
    }

    nonisolated private static func projectKey(forProjectDir dir: URL) -> String {
        let name = dir.lastPathComponent
        if let range = name.range(of: "-Projects-") {
            return String(name[range.upperBound...])
        }
        return name
    }

    // MARK: - Directory watcher

    private func attachDirWatcher() {
        let fd = open(projectsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fsFd = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        let captured = fd
        src.setCancelHandler {
            if captured >= 0 { close(captured) }
        }
        src.resume()
        fsSource = src
    }
}
