import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .init()
    @Published private(set) var isRefreshing: Bool = false

    private let projectsDir: URL = URL(fileURLWithPath:
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects"))

    private var refreshTimer: Timer?
    private var fsSource: DispatchSourceFileSystemObject?
    private var fsFd: Int32 = -1

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        attachDirWatcher()
    }

    deinit {
        refreshTimer?.invalidate()
        fsSource?.cancel()
        if fsFd >= 0 { close(fsFd) }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let dir = projectsDir
        Task.detached(priority: .utility) { [weak self] in
            let result = UsageStore.computeSnapshot(from: dir)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.snapshot = result
                self.isRefreshing = false
            }
        }
    }

    // MARK: - Pure computation (runs off main)

    nonisolated private static func computeSnapshot(from projectsDir: URL) -> UsageSnapshot {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return UsageSnapshot()
        }

        var snap = UsageSnapshot()
        var seenMessageIds = Set<String>()

        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let startOfWeek = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { continue }
            let projectKey = projectKey(forProjectDir: url.deletingLastPathComponent())

            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress else { return }
                var lineStart = 0
                let count = raw.count
                for i in 0..<count {
                    let byte = base.load(fromByteOffset: i, as: UInt8.self)
                    if byte == 0x0A { // '\n'
                        if i > lineStart {
                            let lineData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base.advanced(by: lineStart)),
                                                count: i - lineStart,
                                                deallocator: .none)
                            processLine(
                                lineData,
                                projectKey: projectKey,
                                decoder: decoder,
                                formatter: formatter,
                                formatterNoFrac: formatterNoFrac,
                                seenMessageIds: &seenMessageIds,
                                startOfToday: startOfToday,
                                startOfWeek: startOfWeek,
                                snap: &snap
                            )
                        }
                        lineStart = i + 1
                    }
                }
                if lineStart < count {
                    let lineData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base.advanced(by: lineStart)),
                                        count: count - lineStart,
                                        deallocator: .none)
                    processLine(
                        lineData,
                        projectKey: projectKey,
                        decoder: decoder,
                        formatter: formatter,
                        formatterNoFrac: formatterNoFrac,
                        seenMessageIds: &seenMessageIds,
                        startOfToday: startOfToday,
                        startOfWeek: startOfWeek,
                        snap: &snap
                    )
                }
            }
        }

        snap.lastComputedAt = Date()
        return snap
    }

    nonisolated private static func processLine(
        _ data: Data,
        projectKey: String,
        decoder: JSONDecoder,
        formatter: ISO8601DateFormatter,
        formatterNoFrac: ISO8601DateFormatter,
        seenMessageIds: inout Set<String>,
        startOfToday: Date,
        startOfWeek: Date,
        snap: inout UsageSnapshot
    ) {
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
        guard (raw["type"] as? String) == "assistant" else { return }
        guard let message = raw["message"] as? [String: Any] else { return }
        guard let usage = message["usage"] as? [String: Any] else { return }
        guard let messageId = message["id"] as? String else { return }
        if seenMessageIds.contains(messageId) { return }
        seenMessageIds.insert(messageId)

        guard let timestampStr = raw["timestamp"] as? String else { return }
        let timestamp = formatter.date(from: timestampStr)
            ?? formatterNoFrac.date(from: timestampStr)
        guard let ts = timestamp else { return }

        let modelId = (message["model"] as? String) ?? "unknown"
        let sessionId = (raw["sessionId"] as? String) ?? ""
        let projectKeyFromCwd: String = {
            if let cwd = raw["cwd"] as? String, let last = cwd.split(separator: "/").last {
                return String(last)
            }
            return projectKey
        }()

        let entry = UsageEntry(
            timestamp: ts,
            modelId: modelId,
            projectKey: projectKeyFromCwd,
            sessionId: sessionId,
            messageId: messageId,
            inputTokens: (usage["input_tokens"] as? Int) ?? 0,
            outputTokens: (usage["output_tokens"] as? Int) ?? 0,
            cacheWriteTokens: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
            cacheReadTokens: (usage["cache_read_input_tokens"] as? Int) ?? 0
        )

        if entry.totalTokens == 0 { return }

        snap.entryCount += 1

        var rollup = snap.byProject[entry.projectKey] ?? ProjectRollup()

        if ts >= startOfToday {
            snap.today.add(entry)
            snap.byModelToday[entry.modelId, default: .init()].add(entry)
            rollup.today.add(entry)
            rollup.byModelToday[entry.modelId, default: .init()].add(entry)
        }
        if ts >= startOfWeek {
            snap.thisWeek.add(entry)
            snap.byModelWeek[entry.modelId, default: .init()].add(entry)
            rollup.week.add(entry)
            rollup.byModelWeek[entry.modelId, default: .init()].add(entry)
        }
        snap.allTime.add(entry)
        snap.byModelAll[entry.modelId, default: .init()].add(entry)
        rollup.allTime.add(entry)
        rollup.byModelAll[entry.modelId, default: .init()].add(entry)

        if rollup.firstActivityAt == nil || ts < rollup.firstActivityAt! {
            rollup.firstActivityAt = ts
        }
        if rollup.lastActivityAt == nil || ts > rollup.lastActivityAt! {
            rollup.lastActivityAt = ts
        }
        snap.byProject[entry.projectKey] = rollup
    }

    nonisolated private static func projectKey(forProjectDir dir: URL) -> String {
        // Directory names look like "-Users-sagar-Projects-med-softattention".
        // Take the substring after the last "-Projects-" if present, else the dir name.
        let name = dir.lastPathComponent
        if let range = name.range(of: "-Projects-") {
            return String(name[range.upperBound...])
        }
        return name
    }

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
