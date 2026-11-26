import Foundation
import Security

// Errors shown in the menu when the usage API cannot be used
nonisolated enum UsageAPIError: LocalizedError {
    case noToken
    case unauthorized
    case rateLimited
    case http(Int)
    case unexpectedFormat

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "Claude Code login not found"
        case .unauthorized:
            return "Token expired, use Claude Code to renew it"
        case .rateLimited:
            return "Rate limited, will retry later"
        case .http(let code):
            return "Server returned HTTP \(code)"
        case .unexpectedFormat:
            return "Unexpected response format"
        }
    }
}

// Reads Claude Code's OAuth token and queries the unofficial usage endpoint.
// The token is only read, never refreshed or written, so Claude Code stays signed in.
nonisolated enum UsageAPIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    // Call this off the main thread because the Keychain read can block
    static func fetchUsage() async throws -> UsageState {
        let token = try readAccessToken()

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.unexpectedFormat
        }

        switch http.statusCode {
        case 200..<300:
            return try parse(data)
        case 401, 403:
            throw UsageAPIError.unauthorized
        case 429:
            throw UsageAPIError.rateLimited
        default:
            throw UsageAPIError.http(http.statusCode)
        }
    }

    // Reads the token from the Keychain, or from the file some setups use instead
    private static func readAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let token = accessToken(from: data) {
            return token
        }

        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: fileURL), let token = accessToken(from: data) {
            return token
        }

        throw UsageAPIError.noToken
    }

    // Credentials JSON looks like {"claudeAiOauth": {"accessToken": "..."}}
    private static func accessToken(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any] else {
            return nil
        }
        return oauth["accessToken"] as? String
    }

    // Supports both response shapes seen in other apps:
    // {"limits": [{"kind": "session", "percent": 12, "resets_at": "..."}, ...]}
    // {"five_hour": {"utilization": 12, "resets_at": "..."}, "seven_day": {...}}
    private static func parse(_ data: Data) throws -> UsageState {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.unexpectedFormat
        }

        var fiveHour: UsageWindow?
        var sevenDay: UsageWindow?

        if let limits = root["limits"] as? [[String: Any]] {
            for limit in limits {
                let window = makeWindow(percent: limit["percent"], resetsAt: limit["resets_at"])
                switch limit["kind"] as? String {
                case "session":
                    fiveHour = window
                case "weekly_all":
                    sevenDay = window
                default:
                    break
                }
            }
        } else {
            if let raw = root["five_hour"] as? [String: Any] {
                fiveHour = makeWindow(percent: raw["utilization"], resetsAt: raw["resets_at"])
            }
            if let raw = root["seven_day"] as? [String: Any] {
                sevenDay = makeWindow(percent: raw["utilization"], resetsAt: raw["resets_at"])
            }
        }

        guard fiveHour != nil || sevenDay != nil else {
            throw UsageAPIError.unexpectedFormat
        }
        return UsageState(updatedAt: Date(), fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private static func makeWindow(percent: Any?, resetsAt: Any?) -> UsageWindow? {
        guard let number = percent as? NSNumber else {
            return nil
        }
        return UsageWindow(usedPercentage: number.doubleValue, resetsAt: parseDate(resetsAt))
    }

    // Accepts Unix seconds or ISO 8601 text
    private static func parseDate(_ value: Any?) -> Date? {
        if let seconds = value as? NSNumber {
            return Date(timeIntervalSince1970: seconds.doubleValue)
        }
        guard let text = value as? String else {
            return nil
        }

        // The server may send 6 fractional digits, but the parser accepts only 3
        let trimmed = text.replacingOccurrences(
            of: #"(\.\d{3})\d+"#,
            with: "$1",
            options: .regularExpression
        )
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(trimmed) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(trimmed)
    }
}
