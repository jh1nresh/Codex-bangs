import Foundation

public enum CodexDesktopHandoff {
    public static let maximumPromptUTF8Bytes = 4_000
    private static let maximumEncodedURLBytes = 12_500

    public static func url(for prompt: String) -> URL? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= maximumPromptUTF8Bytes else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "new"
        components.queryItems = [
            URLQueryItem(name: "prompt", value: trimmed)
        ]
        guard let url = components.url,
              url.absoluteString.utf8.count <= maximumEncodedURLBytes else {
            return nil
        }
        return url
    }

    public static func truncatingToMaximumUTF8Bytes(_ prompt: String) -> String {
        var result = ""
        var byteCount = 0

        for character in prompt {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= maximumPromptUTF8Bytes else { break }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }
}
