import Foundation

struct SessionDetailTarget: Hashable, Codable {
    let sessionId: String
    let transcriptPath: String
    let projectName: String
    let cwd: String?
}

struct HourlyBucket: Equatable, Identifiable {
    let hour: Date        // hour-truncated
    var bucket: Bucket
    var id: Date { hour }
}

struct SessionTranscript: Equatable {
    let sessionId: String
    let cwd: String?
    let firstTimestamp: Date?
    let lastTimestamp: Date?
    let modelBuckets: [String: Bucket]    // model id -> bucket
    let hourly: [HourlyBucket]            // chronological
    let toolCounts: [String: Int]
    let filesTouched: [String]            // deduped, first-seen order
    let userMessageCount: Int
    let assistantMessageCount: Int

    var totalBucket: Bucket {
        var b = Bucket()
        for (_, mb) in modelBuckets {
            b.cost              += mb.cost
            b.inputTokens       += mb.inputTokens
            b.outputTokens      += mb.outputTokens
            b.cacheWriteTokens  += mb.cacheWriteTokens
            b.cacheReadTokens   += mb.cacheReadTokens
            b.sessionIds.formUnion(mb.sessionIds)
            if mb.hasUnknownPricing { b.hasUnknownPricing = true }
        }
        return b
    }

    var duration: TimeInterval? {
        guard let f = firstTimestamp, let l = lastTimestamp else { return nil }
        return l.timeIntervalSince(f)
    }
}

/// Tool names that write to the filesystem — used to extract "files touched".
enum SessionTranscriptParser {
    private static let fileWritingTools: Set<String> = [
        "Write", "Edit", "NotebookEdit", "MultiEdit"
    ]

    static func parse(jsonlURL: URL) -> SessionTranscript? {
        guard let data = try? Data(contentsOf: jsonlURL, options: [.mappedIfSafe]),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let cal = Calendar.current
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()
        formatterNoFrac.formatOptions = [.withInternetDateTime]

        var sessionId: String?
        var cwd: String?
        var firstTs: Date?
        var lastTs: Date?
        var modelBuckets: [String: Bucket] = [:]
        var hourly: [Date: Bucket] = [:]
        var toolCounts: [String: Int] = [:]
        var filesOrdered: [String] = []
        var filesSeen: Set<String> = []
        var userCount = 0
        var assistantCount = 0
        var seenMsgIds: Set<String> = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if sessionId == nil, let sid = raw["sessionId"] as? String { sessionId = sid }
            if cwd == nil, let c = raw["cwd"] as? String { cwd = c }

            if let timestampStr = raw["timestamp"] as? String {
                if let ts = formatter.date(from: timestampStr) ?? formatterNoFrac.date(from: timestampStr) {
                    if firstTs == nil || ts < firstTs! { firstTs = ts }
                    if lastTs  == nil || ts > lastTs!  { lastTs  = ts }
                }
            }

            let type = raw["type"] as? String
            if type == "user" { userCount += 1 }
            if type == "assistant" {
                assistantCount += 1
                if let message = raw["message"] as? [String: Any] {
                    if let content = message["content"] as? [[String: Any]] {
                        for block in content {
                            guard (block["type"] as? String) == "tool_use" else { continue }
                            if let name = block["name"] as? String {
                                toolCounts[name, default: 0] += 1
                                if fileWritingTools.contains(name),
                                   let input = block["input"] as? [String: Any],
                                   let path = input["file_path"] as? String,
                                   !filesSeen.contains(path) {
                                    filesSeen.insert(path)
                                    filesOrdered.append(path)
                                }
                            }
                        }
                    }

                    if let usage = message["usage"] as? [String: Any],
                       let messageId = message["id"] as? String,
                       let timestampStr = raw["timestamp"] as? String,
                       let ts = formatter.date(from: timestampStr) ?? formatterNoFrac.date(from: timestampStr),
                       !seenMsgIds.contains(messageId) {
                        seenMsgIds.insert(messageId)
                        let modelId = (message["model"] as? String) ?? "unknown"
                        let cacheCreation = usage["cache_creation"] as? [String: Any]
                        let entry = UsageEntry(
                            timestamp: ts,
                            modelId: modelId,
                            projectKey: cwd.flatMap { $0.split(separator: "/").last.map(String.init) } ?? "",
                            cwd: cwd,
                            sessionId: sessionId ?? "",
                            messageId: messageId,
                            inputTokens:      (usage["input_tokens"] as? Int) ?? 0,
                            outputTokens:     (usage["output_tokens"] as? Int) ?? 0,
                            cacheWriteTokens: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
                            cacheReadTokens:  (usage["cache_read_input_tokens"]  as? Int) ?? 0,
                            ephemeral5mWriteTokens: (cacheCreation?["ephemeral_5m_input_tokens"] as? Int) ?? 0,
                            ephemeral1hWriteTokens: (cacheCreation?["ephemeral_1h_input_tokens"] as? Int) ?? 0
                        )
                        if entry.totalTokens > 0 {
                            modelBuckets[modelId, default: .init()].add(entry)
                            let comps = cal.dateComponents([.year, .month, .day, .hour], from: ts)
                            if let hour = cal.date(from: comps) {
                                hourly[hour, default: .init()].add(entry)
                            }
                        }
                    }
                }
            }
        }

        guard let sid = sessionId else { return nil }

        let orderedHourly = hourly
            .map { HourlyBucket(hour: $0.key, bucket: $0.value) }
            .sorted { $0.hour < $1.hour }

        return SessionTranscript(
            sessionId: sid,
            cwd: cwd,
            firstTimestamp: firstTs,
            lastTimestamp: lastTs,
            modelBuckets: modelBuckets,
            hourly: orderedHourly,
            toolCounts: toolCounts,
            filesTouched: filesOrdered,
            userMessageCount: userCount,
            assistantMessageCount: assistantCount
        )
    }
}
