import Foundation
import Observation

// Reads the usage file and provides text for the menu bar
@MainActor
@Observable
final class UsageStore {
    private(set) var state: UsageState?
    private(set) var errorMessage: String?
    private(set) var now = Date()

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
        reload()

        // Re-read the file every 30 seconds for as long as the app runs
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.reload()
            }
        }
    }

    // Reads and decodes the JSON file
    func reload() {
        now = Date()
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            // resets_at and updated_at are Unix timestamps in seconds
            decoder.dateDecodingStrategy = .secondsSince1970
            state = try decoder.decode(UsageState.self, from: data)
            errorMessage = nil
        } catch {
            // Keep the last good state and only report the problem
            errorMessage = "Could not read usage data"
        }
    }


    // One line in the dropdown menu for a single window
    func detailText(title: String, window: UsageWindow?) -> String {
        guard let window else { return "\(title): no data" }
        if window.hasReset(now: now) {
            return "\(title): reset, waiting for new data"
        }
        return "\(title): \(percentText(window)) used · resets \(resetText(window.resetsAt))"
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
    
    // How long ago the bridge script last wrote the file
    var updatedText: String {
        guard let state else { return errorMessage ?? "No data yet" }
        let minutes = Int(now.timeIntervalSince(state.updatedAt)) / 60
        if minutes < 1 {
            return "Updated just now"
        }
        if minutes < 60 {
            return "Updated \(minutes) min ago"
        }
        return "Updated \(minutes / 60)h \(minutes % 60)m ago"
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
