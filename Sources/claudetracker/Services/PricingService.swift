import Foundation
import Combine

extension Notification.Name {
    static let pricingDidUpdate = Notification.Name("com.sagar.claudetracker.pricingDidUpdate")
}

enum PricingRefreshInterval: Int, CaseIterable, Identifiable {
    case every6h    = 21600
    case every12h   = 43200
    case daily      = 86400
    case manualOnly = 0

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .every6h:    return "Every 6 hours"
        case .every12h:   return "Every 12 hours"
        case .daily:      return "Every day"
        case .manualOnly: return "Manual only"
        }
    }
}

@MainActor
final class PricingService: ObservableObject {
    static let shared = PricingService()

    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var modelCount: Int = 0

    private struct CacheFile: Codable {
        let lastUpdated: Date
        let source: String
        let rates: [String: Pricing.Rates]
    }

    private let sourceURL = URL(string:
        "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!

    private let cacheURL: URL
    private var tickTimer: Timer?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("claudetracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.cacheURL = base.appendingPathComponent("prices.json")

        loadFromCache()
        scheduleTicker()

        // Kick an initial refresh if the cache is missing or looks very stale,
        // even under "manual only" — we want *something* on first launch.
        if lastUpdated == nil || Date().timeIntervalSince(lastUpdated!) > 7 * 86400 {
            Task { await self.refresh() }
        }
    }

    // MARK: - Public API

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: sourceURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "Pricing", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            }
            let parsed = try parse(data: data)
            guard !parsed.isEmpty else {
                throw NSError(domain: "Pricing", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No Claude models in response"])
            }
            Pricing.setLive(parsed)
            let now = Date()
            lastUpdated = now
            modelCount = parsed.count
            lastErrorMessage = nil
            saveCache(rates: parsed, at: now)
            NotificationCenter.default.post(name: .pricingDidUpdate, object: nil)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Cache I/O

    private func loadFromCache() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let cache = try? decoder.decode(CacheFile.self, from: data) else { return }
        Pricing.setLive(cache.rates)
        lastUpdated = cache.lastUpdated
        modelCount = cache.rates.count
    }

    private func saveCache(rates: [String: Pricing.Rates], at date: Date) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let cache = CacheFile(lastUpdated: date, source: sourceURL.absoluteString, rates: rates)
        guard let data = try? encoder.encode(cache) else { return }
        let tmp = cacheURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: cacheURL)
            try FileManager.default.moveItem(at: tmp, to: cacheURL)
        } catch {
            // Non-fatal — we still hold live in memory.
            NSLog("claudetracker: failed to save prices cache: \(error)")
        }
    }

    // MARK: - Parsing

    private func parse(data: Data) throws -> [String: Pricing.Rates] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Pricing", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Malformed JSON"])
        }
        var out: [String: Pricing.Rates] = [:]
        for (name, value) in obj {
            let key = name.lowercased()
            // Keep the table lean: only Claude-family models get cached.
            guard key.contains("claude") else { continue }
            guard let dict = value as? [String: Any] else { continue }
            let input      = (dict["input_cost_per_token"] as? Double) ?? 0
            let output     = (dict["output_cost_per_token"] as? Double) ?? 0
            let cacheWrite = (dict["cache_creation_input_token_cost"] as? Double) ?? 0
            let cacheRead  = (dict["cache_read_input_token_cost"]  as? Double) ?? 0
            if input == 0 && output == 0 { continue }
            out[key] = Pricing.Rates(
                input: input * 1_000_000,
                output: output * 1_000_000,
                cacheWrite: cacheWrite * 1_000_000,
                cacheRead: cacheRead * 1_000_000
            )
        }
        return out
    }

    // MARK: - Auto-refresh

    private func scheduleTicker() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAutoRefresh() }
        }
    }

    private func checkAutoRefresh() {
        let raw = UserDefaults.standard.integer(forKey: SettingsKey.pricingRefreshInterval)
        // 0 encodes "manual only"; skip scheduled refreshes.
        guard raw > 0 else { return }
        let interval = TimeInterval(raw)
        let last = lastUpdated ?? .distantPast
        if Date().timeIntervalSince(last) >= interval {
            Task { await self.refresh() }
        }
    }
}
