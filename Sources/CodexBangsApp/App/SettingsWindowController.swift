import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let hostingController = NSHostingController(
            rootView: SettingsView(model: model)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Codex-bangs Settings"
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.animationBehavior = .documentWindow
        window.center()
        window.setFrameAutosaveName("CodexBangsSettingsWindow")

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }

        NSApp.activate(ignoringOtherApps: true)
        window.level = .normal
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
