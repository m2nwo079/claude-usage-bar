import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    var body: some Scene {
        // A menu bar item instead of a regular window
        MenuBarExtra("Claude Usage", systemImage: "gauge.medium") {
            Text("Hello from the menu bar")

            Divider()

            // Menu bar apps have no Dock icon, so they need their own Quit button
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
