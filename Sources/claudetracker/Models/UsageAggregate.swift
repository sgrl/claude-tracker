import Foundation

struct UsageEntry: Equatable {
    let timestamp: Date
    let modelId: String
    let projectKey: String          // derived from cwd (last path component) or raw dir name
    let cwd: String?                // full cwd when available (for session detail etc.)
    let sessionId: String
    let messageId: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int       // cache_creation_input_tokens (total)
    let cacheReadTokens: Int        // cache_read_input_tokens
    let ephemeral5mWriteTokens: Int // cache_creation.ephemeral_5m_input_tokens
    let ephemeral1hWriteTokens: Int // cache_creation.ephemeral_1h_input_tokens

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

/// Which ephemeral cache window a session's current warmth is anchored to.
enum CacheWindow: Equatable {
    case fiveMin
    case oneHour

    var ttl: TimeInterval {
        switch self {
        case .fiveMin: return 5 * 60
        case .oneHour: return 60 * 60
        }
    }

    var label: String {
        switch self {
        case .fiveMin: return "5m"
        case .oneHour: return "1h"
        }
    }
}

struct SessionCacheState: Equatable, Identifiable {
    let sessionId: String
    let cwd: String?
    let projectKey: String
    let modelId: String
    let firstMessageAt: Date
    let lastMessageAt: Date
    let last5mWriteAt: Date?
    let last1hWriteAt: Date?
    let transcriptURL: URL?
    let bucket: Bucket

    var id: String { sessionId }

    /// Expiry of the most recently written cache key. `nil` when the session
    /// has produced no cache writes yet (rare — only the opening exchange
    /// before any cache anchor has been established).
    var cacheExpiresAt: Date? {
        let five = last5mWriteAt?.addingTimeInterval(CacheWindow.fiveMin.ttl)
        let hour = last1hWriteAt?.addingTimeInterval(CacheWindow.oneHour.ttl)
        switch (five, hour) {
        case (nil, nil):    return nil
        case let (f?, nil): return f
        case let (nil, h?): return h
        case let (f?, h?):  return max(f, h)
        }
    }

    /// Which cache the session currently relies on — i.e. whose expiry will
    /// be the one that matters for the next message. Returns nil if no cache
    /// has been written yet.
    var dominantWindow: CacheWindow? {
        let fExp = last5mWriteAt?.addingTimeInterval(CacheWindow.fiveMin.ttl)
        let hExp = last1hWriteAt?.addingTimeInterval(CacheWindow.oneHour.ttl)
        switch (fExp, hExp) {
        case (nil, nil): return nil
        case (_?, nil):  return .fiveMin
        case (nil, _?):  return .oneHour
        case let (f?, h?):
            return f >= h ? .fiveMin : .oneHour
        }
    }

    var isCacheWarm: Bool {
        if let exp = cacheExpiresAt { return Date() < exp }
        // No cache write yet — treat as warm for the first few minutes so the
        // session still shows up on the active list while it gets going.
        return Date().timeIntervalSince(lastMessageAt) < 300
    }

    var cacheTimeRemaining: TimeInterval {
        guard let exp = cacheExpiresAt else {
            return max(0, 300 - Date().timeIntervalSince(lastMessageAt))
        }
        return max(0, exp.timeIntervalSinceNow)
    }
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
    var todayHourly: [HourlyBucket] = []  // 24 entries, hour 0..23 of the current calendar day
    var sessions: [String: SessionCacheState] = [:]   // keyed by sessionId
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
