import Foundation
import Observation

// Where the numbers currently shown came from
enum UsageSource {
    case api
    case bridgeFile
}

// Reads usage from the API and the bridge file, and provides text for the menu
@MainActor
@Observable
final class UsageStore {
    private(set) var state: UsageState?
    private(set) var source: UsageSource?
    private(set) var fileError: String?
    private(set) var apiError: String?
    private(set) var now = Date()

    // The endpoint is unofficial, so it is called at most once every 5 minutes
    private static let apiInterval: TimeInterval = 300
    private var lastAPIAttempt: Date?
    private var isFetching = false

    // ~/.claude/usage-menubar/state.json
    private let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/usage-menubar/state.json")

    // Fixed English formats so the output does not follow the system language
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    init() {
        reload(force: true)

        // Check every 30 seconds for as long as the app runs
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.reload()
            }
        }
    }

    // Re-reads the bridge file, and calls the API when it is due or forced
    func reload(force: Bool = false) {
        now = Date()
        readBridgeFile()

        let isDue = lastAPIAttempt.map { now.timeIntervalSince($0) >= Self.apiInterval } ?? true
        guard force || isDue, !isFetching else { return }
        isFetching = true
        lastAPIAttempt = now

        Task {
            do {
                // Detached so the Keychain read and network call stay off the main thread
                let apiState = try await Task.detached {
                    try await UsageAPIClient.fetchUsage()
                }.value
                self.apply(apiState, from: .api)
                self.apiError = nil
            } catch {
                self.apiError = error.localizedDescription
            }
            self.isFetching = false
        }
    }

    private func readBridgeFile() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            // resets_at and updated_at are Unix timestamps in seconds
            decoder.dateDecodingStrategy = .secondsSince1970
            apply(try decoder.decode(UsageState.self, from: data), from: .bridgeFile)
            fileError = nil
        } catch {
            fileError = "Could not read bridge file"
        }
    }

    // Keeps whichever data was captured most recently
    private func apply(_ newState: UsageState, from newSource: UsageSource) {
        if let state, state.updatedAt > newState.updatedAt {
            return
        }
        state = newState
        source = newSource
    }

    // One line in the dropdown menu for a single window
    func detailText(title: String, window: UsageWindow?) -> String {
        guard let window else { return "\(title): no data" }
        if window.hasReset(now: now) {
            return "\(title): reset, waiting for new data"
        }
        guard let resetsAt = window.resetsAt else {
            return "\(title): \(percentText(window)) used"
        }
        return "\(title): \(percentText(window)) used · resets \(resetText(resetsAt))"
    }

    // Gauge icon for the menu bar, based on whichever limit is closer to full
    var menuBarSymbol: String {
        let percentages = [state?.fiveHour, state?.sevenDay]
            .compactMap { $0 }
            .filter { !$0.hasReset(now: now) }
            .map { $0.usedPercentage }

        // No data or both windows have reset
        guard let highest = percentages.max() else {
            return "gauge.with.dots.needle.0percent"
        }

        // Pick the gauge whose needle is closest to the actual percentage
        switch highest {
        case ..<17:
            return "gauge.with.dots.needle.0percent"
        case ..<42:
            return "gauge.with.dots.needle.33percent"
        case ..<59:
            return "gauge.with.dots.needle.50percent"
        case ..<84:
            return "gauge.with.dots.needle.67percent"
        default:
            return "gauge.with.dots.needle.100percent"
        }
    }

    // How long ago the shown data was captured, and from where
    var updatedText: String {
        guard let state else { return apiError ?? fileError ?? "No data yet" }
        let via = source == .api ? "API" : "Claude Code"
        let minutes = Int(now.timeIntervalSince(state.updatedAt)) / 60
        if minutes < 1 {
            return "Updated just now via \(via)"
        }
        if minutes < 60 {
            return "Updated \(minutes) min ago via \(via)"
        }
        return "Updated \(minutes / 60)h \(minutes % 60)m ago via \(via)"
    }

    // "--" when there is no data or the window has already reset
    private func percentText(_ window: UsageWindow?) -> String {
        guard let window, !window.hasReset(now: now) else { return "--" }
        return "\(Int(window.usedPercentage.rounded()))%"
    }

    // e.g. "at 10:20 PM (in 0h 54m)" or "Thu 3:00 PM (in 2d 17h)"
    private func resetText(_ date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60

        if hours >= 24 {
            let dayTime = Self.dayTimeFormatter.string(from: date)
            return "\(dayTime) (in \(hours / 24)d \(hours % 24)h)"
        }
        let time = Self.timeFormatter.string(from: date)
        return "at \(time) (in \(hours)h \(minutes)m)"
    }
}
