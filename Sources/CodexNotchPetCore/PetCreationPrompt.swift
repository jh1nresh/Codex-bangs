import Foundation

public enum PetCreationPromptValidationError: Error, Equatable, Sendable {
    case missingName
    case missingAppearance
    case nameTooLong
}

extension PetCreationPromptValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingName:
            return "Enter a name for your pet."
        case .missingAppearance:
            return "Describe how your pet should look and feel."
        case .nameTooLong:
            return "Shorten the pet name so the request can be opened in Codex."
        }
    }
}

public struct PetCreationPrompt: Equatable, Sendable {
    public let name: String
    public let appearance: String
    public let text: String
    public let wasAppearanceTruncated: Bool

    public init(name: String, appearance: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw PetCreationPromptValidationError.missingName
        }

        let trimmedAppearance = appearance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAppearance.isEmpty else {
            throw PetCreationPromptValidationError.missingAppearance
        }

        let fixedText = Self.introduction
            + trimmedName
            + Self.appearanceHeading
            + Self.requirements
        let availableAppearanceBytes = CodexDesktopHandoff.maximumPromptUTF8Bytes
            - fixedText.utf8.count
        guard availableAppearanceBytes > 0 else {
            throw PetCreationPromptValidationError.nameTooLong
        }

        let boundedAppearance = Self.prefix(
            of: trimmedAppearance,
            fittingUTF8Bytes: availableAppearanceBytes
        )
        guard !boundedAppearance.isEmpty else {
            throw PetCreationPromptValidationError.nameTooLong
        }

        let prompt = Self.introduction
            + trimmedName
            + Self.appearanceHeading
            + boundedAppearance
            + Self.requirements

        self.name = trimmedName
        self.appearance = boundedAppearance
        self.text = prompt
        self.wasAppearanceTruncated = boundedAppearance != trimmedAppearance
    }

    private static let introduction = """
    Use $hatch-pet to create a custom Codex pet.

    Pet name:
    """

    private static let appearanceHeading = """


    Appearance and personality:
    """

    private static let requirements = """


    Complete the full Codex v2 8x11 workflow: all nine standard animation rows, four approved cardinal anchors, all 16 clockwise look directions, deterministic atlas and chroma validation, contact-sheet and motion-preview review, independent visual QA, and spriteVersionNumber: 2 packaging. The final installed package must pass every full v2 QA gate before you report success; do not stop at the intermediate 8x9 atlas.

    Install the finished pet under ~/.codex/pets/<pet-id> with pet.json and spritesheet.webp. Do not modify Codex-bangs as part of this request.

    When installation and QA are complete, tell me to return to Codex-bangs and reopen or reload it so I can select the new pet.
    """

    private static func prefix(of value: String, fittingUTF8Bytes maximumBytes: Int) -> String {
        var result = ""
        var byteCount = 0

        for character in value {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= maximumBytes else { break }
            result.append(character)
            byteCount += characterBytes
        }

        return result
    }
}
