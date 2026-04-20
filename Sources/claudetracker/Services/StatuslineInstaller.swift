import Foundation

enum StatuslineInstallStatus: Equatable {
    /// Our bridge markers were found in the script referenced by settings.json.
    case installed(scriptPath: String)
    /// No statusLine configured in settings.json (or no settings.json at all).
    case notConfigured
    /// A statusLine is configured but the script it points to doesn't contain our bridge.
    case externalStatuslineFound(command: String, scriptPath: String?)
}

@MainActor
final class StatuslineInstaller: ObservableObject {
    static let shared = StatuslineInstaller()

    @Published private(set) var status: StatuslineInstallStatus = .notConfigured
    @Published private(set) var lastError: String?

    private let claudeDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude", isDirectory: true)

    private var settingsURL: URL { claudeDir.appendingPathComponent("settings.json") }
    private var managedScriptURL: URL { claudeDir.appendingPathComponent("statusline-claudetracker.sh") }

    // Any of these present in a script = we treat it as installed (covers both
    // the official marker-wrapped install and the hand-patched early version).
    private let installSignatures: [String] = [
        "# --- claudetracker bridge start ---",
        "claudetracker bridge start",
        "claudetracker.app",
        "$HOME/.claude/claudetracker/sessions",
    ]

    private init() {
        refresh()
    }

    // MARK: - Detection

    func refresh() {
        status = computeStatus()
    }

    private func computeStatus() -> StatuslineInstallStatus {
        guard let obj = readJSON(settingsURL) else { return .notConfigured }
        guard let statusLine = obj["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else {
            return .notConfigured
        }
        let scriptPath = extractScriptPath(from: command)
        if let scriptPath,
           let content = try? String(contentsOfFile: scriptPath),
           installSignatures.contains(where: content.contains) {
            return .installed(scriptPath: scriptPath)
        }
        return .externalStatuslineFound(command: command, scriptPath: scriptPath)
    }

    /// `command` examples: "bash /Users/.../script.sh", "bash ~/.claude/x.sh arg1".
    /// We look for the last token that resolves to an existing file.
    private func extractScriptPath(from command: String) -> String? {
        let tokens = command.split(separator: " ").map(String.init)
        for t in tokens.reversed() {
            let expanded = (t as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }
        return nil
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Install / uninstall

    func install() throws {
        lastError = nil
        refresh()
        if case .installed = status { return }
        if case .externalStatuslineFound = status {
            throw NSError(domain: "StatuslineInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "A statusline command is already configured. Use manual setup — the bridge snippet is in Settings."
            ])
        }

        try writeManagedScript()
        try patchSettings()
        refresh()
    }

    func uninstall() throws {
        lastError = nil
        guard case .installed(let path) = status else { return }
        let url = URL(fileURLWithPath: path)
        // Only remove our managed script; never touch a user-owned one.
        if url.lastPathComponent == managedScriptURL.lastPathComponent {
            try? FileManager.default.removeItem(at: url)
        }
        try clearStatusLineFromSettings()
        refresh()
    }

    private func writeManagedScript() throws {
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = Data(Self.bridgeScript.utf8)
        try atomicWrite(data: data, to: managedScriptURL)
        // Make the script executable so a direct path invocation also works.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: managedScriptURL.path
        )
    }

    private func patchSettings() throws {
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        var obj: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            // Refuse to overwrite if the existing file can't be parsed — silently
            // nuking a user's config would be much worse than a clear error.
            guard let parsed = readJSON(settingsURL) else {
                throw NSError(domain: "StatuslineInstaller", code: 2, userInfo: [
                    NSLocalizedDescriptionKey:
                        "~/.claude/settings.json exists but couldn't be parsed as JSON. Fix or move it, then try again."
                ])
            }
            obj = parsed
        }
        obj["statusLine"] = [
            "type": "command",
            "command": "bash \(managedScriptURL.path)",
        ]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try atomicWrite(data: data, to: settingsURL)
    }

    private func clearStatusLineFromSettings() throws {
        guard var obj = readJSON(settingsURL) else { return }
        obj.removeValue(forKey: "statusLine")
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try atomicWrite(data: data, to: settingsURL)
    }

    private func atomicWrite(data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
        // replaceItemAt may succeed silently without the swap on some conditions;
        // as a last resort, make sure tmp is gone if it still exists.
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Bridge script

    /// Shell script installed at ~/.claude/statusline-claudetracker.sh. Mirrors
    /// Claude Code's statusline stdin payload to the two files claudetracker.app
    /// watches. Uses grep/cut so no jq dependency is required.
    static let bridgeScript: String = """
    #!/usr/bin/env bash
    # --- claudetracker bridge start ---
    # Generated by Claude Tracker. Mirrors Claude Code's statusline stdin
    # payload to files claudetracker.app reads. Keep the marker lines intact
    # so the app can detect / update / remove this hook later.
    input=$(cat)

    _ctk_tmp="$HOME/.claude/statusline-input.json.$$.tmp"
    printf '%s' "$input" > "$_ctk_tmp" \\
      && mv "$_ctk_tmp" "$HOME/.claude/statusline-input.json"

    _ctk_sid=$(printf '%s' "$input" \\
      | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]+"' \\
      | head -1 \\
      | cut -d'"' -f4)
    if [ -n "$_ctk_sid" ]; then
      _ctk_dir="$HOME/.claude/claudetracker/sessions"
      mkdir -p "$_ctk_dir"
      _ctk_sess_tmp="$_ctk_dir/${_ctk_sid}.json.$$.tmp"
      printf '%s' "$input" > "$_ctk_sess_tmp" \\
        && mv "$_ctk_sess_tmp" "$_ctk_dir/${_ctk_sid}.json"
    fi
    # --- claudetracker bridge end ---

    # Statusline output — customize freely. Claude Tracker only needs the
    # bridge block above to function.

    """
}
