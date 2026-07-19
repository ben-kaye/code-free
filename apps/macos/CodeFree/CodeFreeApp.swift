import SwiftUI

@main
struct CodeFreeApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppearancePreference.storageKey)
    private var appearanceRaw = AppearancePreference.system.rawValue

    private var preferredScheme: ColorScheme? {
        (AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup("Code Free") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.workspaces)
                .preferredColorScheme(preferredScheme)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    appDelegate.model = model
                    model.start()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    model.newTask()
                }
                .keyboardShortcut("n", modifiers: [.command])
                Button("New Project…") {
                    model.newProject()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Handles terminate → stop sidecar cleanly.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        // Brief window for SIGTERM flush
        Thread.sleep(forTimeInterval: 0.35)
    }
}
