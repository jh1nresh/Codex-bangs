import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var panelController: NotchPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var globalHotKeyService: GlobalHotKeyService?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = NotchPanelController(model: model) { [weak self] in
            self?.openSettings()
        }
        self.panelController = panelController
        configureGlobalHotKey(for: panelController)
        configureStatusItem()

        let arguments = Set(CommandLine.arguments.dropFirst())
        model.start(previewMode: arguments.contains("--preview"))
        panelController.show()
        if arguments.contains("--expanded") {
            panelController.setExpanded(true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        globalHotKeyService?.stop()
        panelController?.tearDown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let packageURLs = urls.filter {
            $0.pathExtension.caseInsensitiveCompare("codexpet") == .orderedSame
        }
        guard !packageURLs.isEmpty else { return }

        for packageURL in packageURLs {
            model.importPetPackage(at: packageURL)
        }
        openSettings()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Codex-bangs"
        )

        let menu = NSMenu()
        menu.addItem(menuItem("Show / Hide", action: #selector(togglePanel)))
        let talkItem = menuItem("Talk to pet", action: #selector(showTalkToPet))
        talkItem.keyEquivalent = " "
        talkItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(talkItem)
        menu.addItem(menuItem("Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Codex-bangs", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func togglePanel() {
        panelController?.toggleVisibility()
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc func openSettings() {
        panelController?.setExpanded(false)

        let controller: SettingsWindowController
        if let settingsWindowController {
            controller = settingsWindowController
        } else {
            let newController = SettingsWindowController(model: model)
            settingsWindowController = newController
            controller = newController
        }
        controller.present()
    }

    @objc private func showTalkToPet() {
        panelController?.showTalkToPet()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureGlobalHotKey(for panelController: NotchPanelController) {
        let service = GlobalHotKeyService { [weak panelController] in
            panelController?.showTalkToPet()
        }
        guard service.start() else {
            model.setTalkShortcutAvailable(false)
            NSLog("Codex-bangs could not register the Control-Option-Space shortcut.")
            return
        }
        model.setTalkShortcutAvailable(true)
        globalHotKeyService = service
    }
}
