import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    // Created once and kept alive for the whole app
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuContent(store: store)
        } label: {
            // Icon and usage text shown together in the menu bar
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                Text(store.menuBarTitle)
            }
        }
    }
}

// Items shown when the menu bar item is clicked
struct UsageMenuContent: View {
    let store: UsageStore

    var body: some View {
        Text(store.detailText(title: "5-hour", window: store.state?.fiveHour))
        Text(store.detailText(title: "Weekly", window: store.state?.sevenDay))

        Divider()

        Text(store.updatedText)

        Button("Refresh") {
            store.reload()
        }
        .keyboardShortcut("r")

        Divider()

        // Menu bar apps have no Dock icon, so they need their own Quit button
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
