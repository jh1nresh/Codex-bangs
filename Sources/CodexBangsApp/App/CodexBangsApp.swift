import SwiftUI

@main
struct CodexBangsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
    }
}
