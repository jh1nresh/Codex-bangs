import AppKit
import CodexNotchPetCore

@MainActor
enum CodexDesktopLauncher {
    static func open(
        prompt: String,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let url = CodexDesktopHandoff.url(for: prompt) else {
            completion(false)
            return
        }

        let workspace = NSWorkspace.shared
        guard let applicationURL = workspace.urlForApplication(toOpen: url),
              CodexDesktopAppVerifier.isTrusted(applicationURL: applicationURL) else {
            completion(false)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { application, error in
            let opened = application != nil && error == nil
            Task { @MainActor in
                completion(opened)
            }
        }
    }
}
