import Foundation

struct StatuslinePayload: Codable, Equatable {
    struct Model: Codable, Equatable {
        let displayName: String?
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }

    struct ContextWindow: Codable, Equatable {
        let usedPercentage: Double?
        enum CodingKeys: String, CodingKey { case usedPercentage = "used_percentage" }
    }

    struct RateLimits: Codable, Equatable {
        struct FiveHour: Codable, Equatable {
            let usedPercentage: Double?
            let resetsAt: TimeInterval?
            enum CodingKeys: String, CodingKey {
                case usedPercentage = "used_percentage"
                case resetsAt = "resets_at"
            }
        }
        struct SevenDay: Codable, Equatable {
            let usedPercentage: Double?
            let resetsAt: TimeInterval?
            enum CodingKeys: String, CodingKey {
                case usedPercentage = "used_percentage"
                case resetsAt = "resets_at"
            }
        }
        let fiveHour: FiveHour?
        let sevenDay: SevenDay?
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    let model: Model?
    let contextWindow: ContextWindow?
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case model
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
    }
}
