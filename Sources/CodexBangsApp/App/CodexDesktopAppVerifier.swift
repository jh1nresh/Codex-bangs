import Foundation
import Security

enum CodexDesktopAppVerifier {
    private static let bundleIdentifier = "com.openai.codex"
    private static let teamIdentifier = "2DC432GLL2"
    private static let codeRequirement = #"anchor apple generic and identifier "com.openai.codex" and certificate leaf[subject.OU] = "2DC432GLL2""#

    static func isTrusted(applicationURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(
            applicationURL as CFURL,
            [],
            &staticCode
        ) == errSecSuccess,
              let staticCode,
              SecRequirementCreateWithString(
                codeRequirement as CFString,
                [],
                &requirement
              ) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess else {
            return false
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &signingInformation
        ) == errSecSuccess,
              let information = signingInformation as? [CFString: Any],
              information[kSecCodeInfoIdentifier] as? String == bundleIdentifier,
              information[kSecCodeInfoTeamIdentifier] as? String == teamIdentifier else {
            return false
        }

        return true
    }
}
