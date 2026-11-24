import Foundation

// Matches the JSON written by usage-bridge.sh
struct UsageState: Decodable {
    let updatedAt: Date
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    // Maps snake_case JSON keys to camelCase Swift properties
    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

// One rate limit window (5-hour or 7-day)
struct UsageWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    // True once the reset time has passed, so the saved percentage is outdated
    func hasReset(now: Date) -> Bool {
        now >= resetsAt
    }
}
