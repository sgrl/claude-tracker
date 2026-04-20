import Foundation

struct SessionState: Equatable, Identifiable {
    let sessionId: String
    let cwd: String?
    let transcriptPath: String?
    let model: Model?
    let cost: Cost?
    let contextWindow: ContextWindow?
    /// File mtime of the per-session bridge file; populated by SessionsBridge, not JSON.
    var lastPingAt: Date?

    var id: String { sessionId }

    struct Model: Equatable {
        let id: String?
        let displayName: String?
    }

    struct Cost: Equatable {
        let totalCostUsd: Double?
        let totalDurationMs: Int?
        let totalApiDurationMs: Int?
        let totalLinesAdded: Int?
        let totalLinesRemoved: Int?
    }

    struct ContextWindow: Equatable {
        let usedPercentage: Double?
        let totalInputTokens: Int?
        let totalOutputTokens: Int?
        let contextWindowSize: Int?
    }
}

// MARK: - Codable via snake_case conversion

extension SessionState: Codable {}
extension SessionState.Model: Codable {}
extension SessionState.Cost: Codable {}
extension SessionState.ContextWindow: Codable {}

enum SessionStateDecoder {
    static let shared: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

extension SessionState {
    var projectName: String {
        guard let cwd, let last = cwd.split(separator: "/").last else { return "—" }
        return String(last)
    }

    var shortModelName: String {
        // "Opus 4.7 (1M context)" → "Opus 4.7"
        guard let name = model?.displayName else { return model?.id ?? "—" }
        if let paren = name.firstIndex(of: "(") {
            return String(name[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        return name
    }
}
