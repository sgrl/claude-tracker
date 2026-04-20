import Foundation

struct UsageEntry: Equatable {
    let timestamp: Date
    let modelId: String
    let projectKey: String          // derived from cwd (last path component) or raw dir name
    let sessionId: String
    let messageId: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int       // cache_creation_input_tokens
    let cacheReadTokens: Int        // cache_read_input_tokens

    var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }

    var cost: Double? {
        Pricing.cost(
            modelId: modelId,
            input: inputTokens,
            output: outputTokens,
            cacheWrite: cacheWriteTokens,
            cacheRead: cacheReadTokens
        )
    }
}

struct Bucket: Equatable {
    var cost: Double = 0
    var hasUnknownPricing: Bool = false
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var cacheReadTokens: Int = 0
    var sessionIds: Set<String> = []

    var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }

    mutating func add(_ entry: UsageEntry) {
        if let c = entry.cost { cost += c } else { hasUnknownPricing = true }
        inputTokens += entry.inputTokens
        outputTokens += entry.outputTokens
        cacheWriteTokens += entry.cacheWriteTokens
        cacheReadTokens += entry.cacheReadTokens
        sessionIds.insert(entry.sessionId)
    }
}

struct UsageSnapshot: Equatable {
    var today: Bucket = .init()
    var thisWeek: Bucket = .init()
    var byModelToday: [String: Bucket] = [:]   // key: modelId
    var byProjectToday: [String: Bucket] = [:] // key: projectKey
    var entryCount: Int = 0
    var lastComputedAt: Date = .distantPast
}
