import Darwin
import Foundation

public struct CodexSkillMetadata: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let directoryURL: URL

    public var name: String {
        id
    }

    public init(id: String, directoryURL: URL) {
        self.id = id
        self.directoryURL = directoryURL
    }
}

public struct CachedCodexPluginPackage: Identifiable, Codable, Equatable, Sendable {
    public let marketplace: String
    public let name: String
    public let version: String
    public let packageURL: URL

    public var id: String {
        "\(name)@\(marketplace):\(version)"
    }

    public init(marketplace: String, name: String, version: String, packageURL: URL) {
        self.marketplace = marketplace
        self.name = name
        self.version = version
        self.packageURL = packageURL
    }
}

public enum CodexPluginManagement: String, Codable, Equatable, Sendable {
    case managedByCodex
}

public struct ConfiguredCodexPlugin: Identifiable, Codable, Equatable, Sendable {
    public let name: String
    public let marketplace: String
    public let cachedPackages: [CachedCodexPluginPackage]
    public let management: CodexPluginManagement

    public var id: String {
        "\(name)@\(marketplace)"
    }

    public init(
        name: String,
        marketplace: String,
        cachedPackages: [CachedCodexPluginPackage],
        management: CodexPluginManagement = .managedByCodex
    ) {
        self.name = name
        self.marketplace = marketplace
        self.cachedPackages = cachedPackages
        self.management = management
    }
}

public enum AgentPetRole: String, CaseIterable, Codable, Equatable, Sendable {
    case builder
    case reviewer
    case guide
    case custom
}

public struct AgentPetProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var role: AgentPetRole
    public var petID: String
    public var selectedSkillIDs: [String] {
        didSet {
            selectedSkillIDs = Self.normalizedSkillIDs(selectedSkillIDs)
        }
    }

    public var skillPromptPrefix: String {
        Self.normalizedSkillIDs(selectedSkillIDs)
            .map { "$\($0)" }
            .joined(separator: " ")
    }

    public init(
        id: String,
        name: String,
        role: AgentPetRole,
        petID: String,
        selectedSkillIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.petID = petID
        self.selectedSkillIDs = Self.normalizedSkillIDs(selectedSkillIDs)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        role = try container.decode(AgentPetRole.self, forKey: .role)
        petID = try container.decode(String.self, forKey: .petID)
        selectedSkillIDs = Self.normalizedSkillIDs(
            try container.decode([String].self, forKey: .selectedSkillIDs)
        )
    }

    public static let builtIns: [AgentPetProfile] = [
        AgentPetProfile(
            id: "builder",
            name: "Builder",
            role: .builder,
            petID: PetV2Contract.builtInPetIdentifier
        ),
        AgentPetProfile(
            id: "reviewer",
            name: "Reviewer",
            role: .reviewer,
            petID: PetV2Contract.builtInPetIdentifier
        ),
        AgentPetProfile(
            id: "guide",
            name: "Guide",
            role: .guide,
            petID: PetV2Contract.builtInPetIdentifier
        )
    ]

    private static func normalizedSkillIDs(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers.filter { identifier in
            CapabilityNameValidator.isSafeSkillIdentifier(identifier)
                && seen.insert(identifier).inserted
        }
    }
}

public enum CodexCapabilityDiscovery {
    public static let maximumConfigByteCount = 1_048_576

    public static var defaultSkillsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/skills", isDirectory: true)
    }

    public static var defaultPluginsCacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/plugins/cache", isDirectory: true)
    }

    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml", isDirectory: false)
    }

    public static func discoverSkills(
        in skillsRoot: URL = defaultSkillsRoot,
        fileManager: FileManager = .default
    ) -> [CodexSkillMetadata] {
        guard FileKind.isDirectoryWithoutFollowingSymlink(skillsRoot) else {
            return []
        }

        return directoryContents(of: skillsRoot, fileManager: fileManager).compactMap { candidate in
            let identifier = candidate.lastPathComponent
            guard CapabilityNameValidator.isSafeSkillIdentifier(identifier),
                  FileKind.isDirectoryWithoutFollowingSymlink(candidate),
                  FileKind.isRegularFileWithoutFollowingSymlink(
                    candidate.appendingPathComponent("SKILL.md", isDirectory: false)
                  ) else {
                return nil
            }

            return CodexSkillMetadata(
                id: identifier,
                directoryURL: candidate.standardizedFileURL
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public static func discoverConfiguredPlugins(
        configURL: URL = defaultConfigURL,
        pluginsCacheRoot: URL = defaultPluginsCacheRoot,
        fileManager: FileManager = .default
    ) -> [ConfiguredCodexPlugin] {
        let configuredIdentifiers = configuredPluginIdentifiers(in: configURL)
        guard !configuredIdentifiers.isEmpty else { return [] }

        let cachedPackages = discoverCachedPluginPackages(
            in: pluginsCacheRoot,
            fileManager: fileManager
        )
        let packagesByPlugin = Dictionary(grouping: cachedPackages) {
            PluginIdentifier(name: $0.name, marketplace: $0.marketplace)
        }

        return configuredIdentifiers.map { identifier in
            ConfiguredCodexPlugin(
                name: identifier.name,
                marketplace: identifier.marketplace,
                cachedPackages: packagesByPlugin[identifier] ?? []
            )
        }
        .sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    public static func discoverCachedPluginPackages(
        in pluginsCacheRoot: URL = defaultPluginsCacheRoot,
        fileManager: FileManager = .default
    ) -> [CachedCodexPluginPackage] {
        guard FileKind.isDirectoryWithoutFollowingSymlink(pluginsCacheRoot) else {
            return []
        }

        var packages: [CachedCodexPluginPackage] = []
        for marketplaceURL in directoryContents(of: pluginsCacheRoot, fileManager: fileManager) {
            let marketplace = marketplaceURL.lastPathComponent
            guard CapabilityNameValidator.isSafePathComponent(marketplace),
                  FileKind.isDirectoryWithoutFollowingSymlink(marketplaceURL) else {
                continue
            }

            for pluginURL in directoryContents(of: marketplaceURL, fileManager: fileManager) {
                let name = pluginURL.lastPathComponent
                guard CapabilityNameValidator.isSafePathComponent(name),
                      FileKind.isDirectoryWithoutFollowingSymlink(pluginURL) else {
                    continue
                }

                for versionURL in directoryContents(of: pluginURL, fileManager: fileManager) {
                    let version = versionURL.lastPathComponent
                    let metadataDirectory = versionURL.appendingPathComponent(
                        ".codex-plugin",
                        isDirectory: true
                    )
                    let manifestURL = metadataDirectory.appendingPathComponent(
                        "plugin.json",
                        isDirectory: false
                    )
                    guard CapabilityNameValidator.isSafePathComponent(version),
                          FileKind.isDirectoryWithoutFollowingSymlink(versionURL),
                          FileKind.isDirectoryWithoutFollowingSymlink(metadataDirectory),
                          FileKind.isRegularFileWithoutFollowingSymlink(manifestURL) else {
                        continue
                    }

                    packages.append(
                        CachedCodexPluginPackage(
                            marketplace: marketplace,
                            name: name,
                            version: version,
                            packageURL: versionURL.standardizedFileURL
                        )
                    )
                }
            }
        }

        return packages.sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private static func configuredPluginIdentifiers(in configURL: URL) -> [PluginIdentifier] {
        guard let data = FileKind.readRegularFile(
            at: configURL,
            maximumByteCount: maximumConfigByteCount
        ),
              let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        var seen = Set<PluginIdentifier>()
        return contents.split(whereSeparator: \Character.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let prefix = "[plugins.\""
            let suffix = "\"]"
            guard line.hasPrefix(prefix), line.hasSuffix(suffix) else {
                return nil
            }

            let start = line.index(line.startIndex, offsetBy: prefix.count)
            let end = line.index(line.endIndex, offsetBy: -suffix.count)
            let payload = String(line[start..<end])
            let components = payload.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { return nil }

            let identifier = PluginIdentifier(
                name: String(components[0]),
                marketplace: String(components[1])
            )
            guard CapabilityNameValidator.isSafePathComponent(identifier.name),
                  CapabilityNameValidator.isSafePathComponent(identifier.marketplace),
                  seen.insert(identifier).inserted else {
                return nil
            }
            return identifier
        }
    }

    private static func directoryContents(
        of directory: URL,
        fileManager: FileManager
    ) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

private struct PluginIdentifier: Hashable {
    let name: String
    let marketplace: String
}

private enum CapabilityNameValidator {
    static func isSafeSkillIdentifier(_ identifier: String) -> Bool {
        isSafeASCIIIdentifier(identifier, allowedPunctuation: ["-", "_"])
    }

    static func isSafePathComponent(_ component: String) -> Bool {
        isSafeASCIIIdentifier(component, allowedPunctuation: ["-", "_", ".", "+"])
    }

    private static func isSafeASCIIIdentifier(
        _ identifier: String,
        allowedPunctuation: Set<Character>
    ) -> Bool {
        guard !identifier.isEmpty,
              identifier.utf8.count <= 128,
              identifier != ".",
              identifier != "..",
              let first = identifier.first,
              first.isASCII,
              first.isLetter || first.isNumber else {
            return false
        }

        return identifier.allSatisfy { character in
            character.isASCII
                && (character.isLetter || character.isNumber || allowedPunctuation.contains(character))
        }
    }
}

private enum FileKind {
    static func isDirectoryWithoutFollowingSymlink(_ url: URL) -> Bool {
        fileType(at: url) == mode_t(S_IFDIR)
    }

    static func isRegularFileWithoutFollowingSymlink(_ url: URL) -> Bool {
        fileType(at: url) == mode_t(S_IFREG)
    }

    static func readRegularFile(at url: URL, maximumByteCount: Int) -> Data? {
        guard url.isFileURL else { return nil }

        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_size >= 0,
              metadata.st_size <= maximumByteCount else {
            return nil
        }

        guard let data = try? handle.read(upToCount: maximumByteCount + 1),
              data.count <= maximumByteCount else {
            return nil
        }
        return data
    }

    private static func fileType(at url: URL) -> mode_t? {
        guard url.isFileURL else { return nil }
        var metadata = stat()
        let result = url.path.withCString { path in
            lstat(path, &metadata)
        }
        guard result == 0 else { return nil }
        return metadata.st_mode & mode_t(S_IFMT)
    }
}
