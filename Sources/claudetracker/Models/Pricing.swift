import Foundation

// USD per 1M tokens. Public list prices — update as Anthropic publishes changes.
enum Pricing {
    struct Rates: Equatable, Codable {
        let input: Double
        let output: Double
        let cacheWrite: Double  // cache_creation_input_tokens
        let cacheRead: Double   // cache_read_input_tokens
    }

    // Lock-protected live rates populated by PricingService on successful fetch.
    // Keys are lowercased model identifiers as they appear in LiteLLM (e.g. "claude-opus-4-7").
    private static let liveLock = NSLock()
    private static var _live: [String: Rates] = [:]

    static func setLive(_ rates: [String: Rates]) {
        liveLock.lock(); defer { liveLock.unlock() }
        _live = rates
    }

    static func liveSnapshot() -> [String: Rates] {
        liveLock.lock(); defer { liveLock.unlock() }
        return _live
    }

    // First substring match (case-insensitive) against the model id wins.
    // Ordering is critical: more-specific keys (e.g. "opus-4-7") must come before
    // less-specific ones (e.g. "opus-4", "opus"). Prices sourced from LiteLLM's
    // model_prices_and_context_window.json (which ccusage also uses).
    private static let table: [(pattern: String, rates: Rates)] = [
        // Opus 4.5 / 4.7 — priced down from Opus 4 / 4.1
        ("opus-4-7",   Rates(input:  5.00, output: 25.00, cacheWrite:  6.25, cacheRead: 0.50)),
        ("opus-4-5",   Rates(input:  5.00, output: 25.00, cacheWrite:  6.25, cacheRead: 0.50)),
        // Opus 4 / 4.1 — original Opus pricing
        ("opus-4-1",   Rates(input: 15.00, output: 75.00, cacheWrite: 18.75, cacheRead: 1.50)),
        ("opus-4",     Rates(input: 15.00, output: 75.00, cacheWrite: 18.75, cacheRead: 1.50)),
        ("opus",       Rates(input: 15.00, output: 75.00, cacheWrite: 18.75, cacheRead: 1.50)),
        // Sonnet 4.x
        ("sonnet-4-6", Rates(input:  3.00, output: 15.00, cacheWrite:  3.75, cacheRead: 0.30)),
        ("sonnet-4-5", Rates(input:  3.00, output: 15.00, cacheWrite:  3.75, cacheRead: 0.30)),
        ("sonnet-4",   Rates(input:  3.00, output: 15.00, cacheWrite:  3.75, cacheRead: 0.30)),
        ("sonnet",     Rates(input:  3.00, output: 15.00, cacheWrite:  3.75, cacheRead: 0.30)),
        // Haiku 4.x
        ("haiku-4-5",  Rates(input:  1.00, output:  5.00, cacheWrite:  1.25, cacheRead: 0.10)),
        ("haiku",      Rates(input:  1.00, output:  5.00, cacheWrite:  1.25, cacheRead: 0.10)),
    ]

    static func rates(for modelId: String) -> Rates? {
        let key = modelId.lowercased()
        let live = liveSnapshot()
        // 1. Exact live match.
        if let r = live[key] { return r }
        // 2. Substring live match in either direction (handles bracketed suffixes like "claude-opus-4-7[1m]").
        for (liveKey, rates) in live where key.contains(liveKey) || liveKey.contains(key) {
            return rates
        }
        // 3. Fallback to hardcoded pattern table (seed/offline path).
        return table.first { key.contains($0.pattern) }?.rates
    }

    static func cost(
        modelId: String,
        input: Int,
        output: Int,
        cacheWrite: Int,
        cacheRead: Int
    ) -> Double? {
        guard let r = rates(for: modelId) else { return nil }
        return (Double(input)      * r.input
              + Double(output)     * r.output
              + Double(cacheWrite) * r.cacheWrite
              + Double(cacheRead)  * r.cacheRead) / 1_000_000.0
    }
}
