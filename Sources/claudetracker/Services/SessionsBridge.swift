import Foundation
import Combine

@MainActor
final class SessionsBridge: ObservableObject {
    @Published private(set) var sessions: [SessionState] = []

    private let dir: URL = URL(fileURLWithPath:
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/claudetracker/sessions"))

    // A session is "active" when its bridge file was last touched within this window.
    private let activeWindow: TimeInterval = 600   // 10 minutes

    // Files older than this get pruned on reload so the dir doesn't grow forever.
    private let maxAge: TimeInterval = 86_400      // 24 hours

    private var fsSource: DispatchSourceFileSystemObject?
    private var fsFd: Int32 = -1
    private var pollTimer: Timer?

    init() {
        ensureDirExists()
        reload()
        attachDirWatcher()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    deinit {
        fsSource?.cancel()
        if fsFd >= 0 { close(fsFd) }
        pollTimer?.invalidate()
    }

    var activeSessions: [SessionState] {
        let cutoff = Date().addingTimeInterval(-activeWindow)
        return sessions.filter { ($0.lastPingAt ?? .distantPast) > cutoff }
    }

    private func ensureDirExists() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            sessions = []
            return
        }

        let decoder = SessionStateDecoder.shared
        let pruneCutoff = Date().addingTimeInterval(-maxAge)
        var result: [SessionState] = []

        for file in files where file.pathExtension == "json" {
            let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil

            if let m = mtime, m < pruneCutoff {
                try? fm.removeItem(at: file)
                continue
            }

            guard let data = try? Data(contentsOf: file),
                  var state = try? decoder.decode(SessionState.self, from: data) else { continue }
            state.lastPingAt = mtime
            result.append(state)
        }

        sessions = result.sorted {
            ($0.lastPingAt ?? .distantPast) > ($1.lastPingAt ?? .distantPast)
        }
    }

    private func attachDirWatcher() {
        fsSource?.cancel()
        if fsFd >= 0 { close(fsFd); fsFd = -1 }
        fsFd = open(dir.path, O_EVTONLY)
        guard fsFd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fsFd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        let captured = fsFd
        src.setCancelHandler {
            if captured >= 0 { close(captured) }
        }
        src.resume()
        fsSource = src
    }
}
