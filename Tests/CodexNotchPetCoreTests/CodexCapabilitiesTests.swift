import Foundation
import XCTest
@testable import CodexNotchPetCore

final class CodexCapabilitiesTests: XCTestCase {
    func testSkillDiscoveryReturnsOnlySafeDirectDirectoriesWithRegularManifest() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let alpha = try makeSkill(named: "alpha-skill", in: root)
        _ = try makeSkill(named: "zeta_skill", in: root)
        _ = try makeSkill(named: "unsafe skill", in: root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("missing-manifest", isDirectory: true),
            withIntermediateDirectories: false
        )
        let linked = root.appendingPathComponent("linked-skill", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: alpha)

        let manifestTarget = root.appendingPathComponent("manifest-target")
        try Data("not read".utf8).write(to: manifestTarget)
        let linkedManifestSkill = root.appendingPathComponent("linked-manifest", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedManifestSkill, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: linkedManifestSkill.appendingPathComponent("SKILL.md"),
            withDestinationURL: manifestTarget
        )

        let discovered = CodexCapabilityDiscovery.discoverSkills(in: root)

        XCTAssertEqual(discovered.map(\.id), ["alpha-skill", "zeta_skill"])
        XCTAssertEqual(discovered.first?.name, "alpha-skill")
        XCTAssertEqual(discovered.first?.directoryURL, alpha)
    }

    func testSkillDiscoveryRejectsSymlinkedRoot() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let realRoot = parent.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: false)
        _ = try makeSkill(named: "safe", in: realRoot)
        let linkedRoot = parent.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)

        XCTAssertTrue(CodexCapabilityDiscovery.discoverSkills(in: linkedRoot).isEmpty)
    }

    func testConfiguredPluginDiscoveryReadsOnlyStrictSectionsAndMatchesExactCache() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("config.toml")
        try Data(
            """
            model = "secret-value-that-must-not-be-metadata"
            [plugins."github@openai-curated"]
            enabled = true
            [plugins."missing@openai-curated"]
            enabled = false
            [plugins."bad name@openai-curated"]
            [plugins."github@openai-curated"]
            """.utf8
        ).write(to: configURL)

        let cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: false)
        let github = try makeCachedPlugin(
            marketplace: "openai-curated",
            name: "github",
            version: "1.2.3+4",
            in: cacheRoot
        )
        _ = try makeCachedPlugin(
            marketplace: "openai-curated-remote",
            name: "github",
            version: "9.9.9",
            in: cacheRoot
        )

        let plugins = CodexCapabilityDiscovery.discoverConfiguredPlugins(
            configURL: configURL,
            pluginsCacheRoot: cacheRoot
        )

        XCTAssertEqual(plugins.map(\.id), ["github@openai-curated", "missing@openai-curated"])
        XCTAssertEqual(plugins[0].management, .managedByCodex)
        XCTAssertEqual(plugins[0].cachedPackages.map(\.version), ["1.2.3+4"])
        XCTAssertEqual(plugins[0].cachedPackages.first?.packageURL, github)
        XCTAssertTrue(plugins[1].cachedPackages.isEmpty)
        XCTAssertFalse(String(describing: plugins).contains("secret-value"))
    }

    func testPluginCacheDiscoveryRejectsUnsafeMissingAndSymlinkedComponents() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }

        let cacheRoot = parent.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: false)
        _ = try makeCachedPlugin(
            marketplace: "source",
            name: "valid-plugin",
            version: "0.1.7+1",
            in: cacheRoot
        )

        let missingManifest = cacheRoot
            .appendingPathComponent("source/missing/1.0/.codex-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: missingManifest, withIntermediateDirectories: true)

        let unsafe = cacheRoot
            .appendingPathComponent("source/unsafe plugin/1.0/.codex-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: unsafe.appendingPathComponent("plugin.json"))

        let realPlugin = cacheRoot.appendingPathComponent("source/valid-plugin", isDirectory: true)
        let linkedPlugin = cacheRoot.appendingPathComponent("source/linked-plugin", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedPlugin, withDestinationURL: realPlugin)

        let packages = CodexCapabilityDiscovery.discoverCachedPluginPackages(in: cacheRoot)

        XCTAssertEqual(packages.map(\.id), ["valid-plugin@source:0.1.7+1"])
    }

    func testPluginDiscoveryRejectsSymlinkedAndOversizedConfig() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let realConfig = root.appendingPathComponent("real.toml")
        try Data("[plugins.\"github@openai-curated\"]".utf8).write(to: realConfig)
        let linkedConfig = root.appendingPathComponent("linked.toml")
        try FileManager.default.createSymbolicLink(at: linkedConfig, withDestinationURL: realConfig)

        let oversizedConfig = root.appendingPathComponent("oversized.toml")
        try Data(
            repeating: 0x20,
            count: CodexCapabilityDiscovery.maximumConfigByteCount + 1
        ).write(to: oversizedConfig)

        XCTAssertTrue(
            CodexCapabilityDiscovery.discoverConfiguredPlugins(
                configURL: linkedConfig,
                pluginsCacheRoot: root
            ).isEmpty
        )
        XCTAssertTrue(
            CodexCapabilityDiscovery.discoverConfiguredPlugins(
                configURL: oversizedConfig,
                pluginsCacheRoot: root
            ).isEmpty
        )
    }

    func testAgentProfilesNormalizeSkillNamesAndRoundTrip() throws {
        var profile = AgentPetProfile(
            id: "focused-builder",
            name: "Focused Builder",
            role: .builder,
            petID: "miaomiao",
            selectedSkillIDs: [
                "founder-engineering-workflow",
                "unsafe skill",
                "founder-engineering-workflow",
                "review_and_iterate",
                "evil\n$second"
            ]
        )

        XCTAssertEqual(
            profile.selectedSkillIDs,
            ["founder-engineering-workflow", "review_and_iterate"]
        )
        XCTAssertEqual(
            profile.skillPromptPrefix,
            "$founder-engineering-workflow $review_and_iterate"
        )

        profile.selectedSkillIDs.append("unsafe skill\n$second")
        XCTAssertEqual(
            profile.selectedSkillIDs,
            ["founder-engineering-workflow", "review_and_iterate"]
        )
        XCTAssertEqual(
            profile.skillPromptPrefix,
            "$founder-engineering-workflow $review_and_iterate"
        )

        let decoded = try JSONDecoder().decode(
            AgentPetProfile.self,
            from: JSONEncoder().encode(profile)
        )
        XCTAssertEqual(
            decoded.selectedSkillIDs,
            ["founder-engineering-workflow", "review_and_iterate"]
        )
    }

    func testBuiltInProfilesAreStableAndUseBundledPet() {
        XCTAssertEqual(AgentPetProfile.builtIns.map(\.id), ["builder", "reviewer", "guide"])
        XCTAssertEqual(AgentPetProfile.builtIns.map(\.role), [.builder, .reviewer, .guide])
        XCTAssertTrue(
            AgentPetProfile.builtIns.allSatisfy {
                $0.petID == PetV2Contract.builtInPetIdentifier
                    && $0.selectedSkillIDs.isEmpty
                    && $0.skillPromptPrefix.isEmpty
            }
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeSkill(named name: String, in root: URL) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("This content must not be parsed.".utf8).write(
            to: directory.appendingPathComponent("SKILL.md")
        )
        return directory
    }

    @discardableResult
    private func makeCachedPlugin(
        marketplace: String,
        name: String,
        version: String,
        in cacheRoot: URL
    ) throws -> URL {
        let packageURL = cacheRoot
            .appendingPathComponent(marketplace, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        let metadataURL = packageURL.appendingPathComponent(".codex-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try Data("{\"private\":\"must not be parsed\"}".utf8).write(
            to: metadataURL.appendingPathComponent("plugin.json")
        )
        return packageURL
    }
}
