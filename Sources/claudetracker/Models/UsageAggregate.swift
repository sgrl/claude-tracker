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

/// Scope of time window a view is showing.
enum Scope: String, CaseIterable, Identifiable {
    case today, week, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "Today"
        case .week:  return "7 days"
        case .all:   return "All time"
        }
    }
}

struct ProjectRollup: Equatable {
    var today: Bucket = .init()
    var week: Bucket = .init()
    var allTime: Bucket = .init()
    var byModelToday: [String: Bucket] = [:]
    var byModelWeek: [String: Bucket] = [:]
    var byModelAll: [String: Bucket] = [:]
    var lastActivityAt: Date?
    var firstActivityAt: Date?

    func bucket(for scope: Scope) -> Bucket {
        switch scope {
        case .today: return today
        case .week:  return week
        case .all:   return allTime
        }
    }

    func byModel(for scope: Scope) -> [String: Bucket] {
        switch scope {
        case .today: return byModelToday
        case .week:  return byModelWeek
        case .all:   return byModelAll
        }
    }
}

struct DailyBucket: Equatable, Identifiable {
    let day: Date       // startOfDay
    var bucket: Bucket
    var id: Date { day }
}

struct UsageSnapshot: Equatable {
    var today: Bucket = .init()
    var thisWeek: Bucket = .init()
    var allTime: Bucket = .init()
    var byModelToday: [String: Bucket] = [:]
    var byModelWeek: [String: Bucket] = [:]
    var byModelAll: [String: Bucket] = [:]
    var byProject: [String: ProjectRollup] = [:]
    var dailyLast7: [DailyBucket] = []  // chronological: oldest first, includes today
    var entryCount: Int = 0
    var lastComputedAt: Date = .distantPast

    func topLevelBucket(for scope: Scope) -> Bucket {
        switch scope {
        case .today: return today
        case .week:  return thisWeek
        case .all:   return allTime
        }
    }
}
