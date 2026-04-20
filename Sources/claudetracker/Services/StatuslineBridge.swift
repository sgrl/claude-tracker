import Foundation
import Combine

@MainActor
final class StatuslineBridge: ObservableObject {
    @Published private(set) var snapshot: StatuslinePayload?
    @Published private(set) var fileModified: Date?
    @Published private(set) var lastReloadAt: Date = .distantPast

    private let url: URL = URL(fileURLWithPath:
        (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusline-input.json"))

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pollTimer: Timer?

    // Consider the bridge fresh if the file was written in the last hour.
    // Beyond that, the 5h % may be stale (no active session in a while).
    var isFresh: Bool {
        guard let m = fileModified else { return false }
        return Date().timeIntervalSince(m) < 3600
    }

    init() {
        reload()
        attachWatcher()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    deinit {
        source?.cancel()
        if fd >= 0 { close(fd) }
        pollTimer?.invalidate()
    }

    func reload() {
        defer { lastReloadAt = Date() }
        guard let data = try? Data(contentsOf: url) else {
            snapshot = nil
            fileModified = nil
            return
        }
        snapshot = try? JSONDecoder().decode(StatuslinePayload.self, from: data)
        fileModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
    }

    private func reloadIfChanged() {
        let newMod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        if newMod != fileModified {
            reload()
            attachWatcher() // atomic rename swaps the inode; re-open
        }
    }

    private func attachWatcher() {
        source?.cancel()
        if fd >= 0 { close(fd); fd = -1 }
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        let capturedFd = fd
        src.setCancelHandler {
            if capturedFd >= 0 { close(capturedFd) }
        }
        src.resume()
        source = src
    }
}
