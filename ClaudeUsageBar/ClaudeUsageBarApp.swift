import SwiftUI
import ServiceManagement

@main
struct ClaudeUsageBarApp: App {
    // Created once and kept alive for the whole app
    @State private var store = UsageStore()

    var body: some Scene {
        // Only the icon appears in the menu bar; the title is used for accessibility
        MenuBarExtra("Claude Usage", systemImage: store.menuBarSymbol) {
            UsageMenuContent(store: store)
        }
    }
}

// Items shown when the menu bar item is clicked
struct UsageMenuContent: View {
    let store: UsageStore

    // Reflects whether the app is currently registered as a login item
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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

        // Shown as a checkmark item in the menu
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin },
            set: { setLaunchAtLogin($0) }
        ))

        // Menu bar apps have no Dock icon, so they need their own Quit button
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // Registers or unregisters the app as a login item
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
        // Always read back the real status so the checkmark never lies
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
