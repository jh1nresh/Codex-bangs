import Foundation
import XCTest
@testable import CodexNotchPetCore

final class HatchPetSkillInstallerTests: XCTestCase {
    func testInstallsAllowlistedRuntimeAtomicallyWithoutCopyingOtherTopLevelItems() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let source = try makeBundledSkill(in: base)
        try Data("do not copy".utf8).write(
            to: source.appendingPathComponent("internal-note.txt")
        )
        let excludedTests = source.appendingPathComponent("tests", isDirectory: true)
        try FileManager.default.createDirectory(
            at: excludedTests,
            withIntermediateDirectories: false
        )
        try Data("excluded".utf8).write(
            to: excludedTests.appendingPathComponent("test_runtime.py")
        )

        let codexRoot = base.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: false)
        let skillsRoot = codexRoot.appendingPathComponent("skills", isDirectory: true)

        let installed = try HatchPetSkillInstaller.install(
            bundledSkillAt: source,
            into: skillsRoot
        )

        XCTAssertEqual(
            installed,
            skillsRoot.appendingPathComponent("hatch-pet", isDirectory: true)
        )
        XCTAssertEqual(
            try childNames(of: installed),
            ["LICENSE.txt", "SKILL.md", "agents", "references", "scripts"]
        )
        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("LICENSE.txt")),
            Data("Apache License fixture".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: installed.appendingPathComponent("scripts/prepare_pet_run.py")),
            Data("print('prepare')\n".utf8)
        )
        XCTAssertEqual(HatchPetSkillInstaller.presence(in: skillsRoot), .installed)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installed.appendingPathComponent("internal-note.txt").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: installed.appendingPathComponent("tests").path
            )
        )
        XCTAssertFalse(
            try childNames(of: skillsRoot).contains(where: { $0.hasPrefix(".hatch-pet-install-") })
        )
    }

    func testNeverOverwritesExistingDirectoryFileOrSymlink() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try makeBundledSkill(in: base)

        for existingKind in ["directory", "file", "symlink"] {
            let caseRoot = base.appendingPathComponent(existingKind, isDirectory: true)
            try FileManager.default.createDirectory(at: caseRoot, withIntermediateDirectories: false)
            let skillsRoot = caseRoot.appendingPathComponent("skills", isDirectory: true)
            try FileManager.default.createDirectory(
                at: skillsRoot,
                withIntermediateDirectories: false
            )
            let destination = HatchPetSkillInstaller.destinationURL(in: skillsRoot)

            switch existingKind {
            case "directory":
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: false
                )
                try Data("keep".utf8).write(to: destination.appendingPathComponent("marker"))
            case "file":
                try Data("keep-file".utf8).write(to: destination)
            default:
                let target = caseRoot.appendingPathComponent("target", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: target,
                    withIntermediateDirectories: false
                )
                try FileManager.default.createSymbolicLink(
                    at: destination,
                    withDestinationURL: target
                )
            }

            XCTAssertThrowsError(
                try HatchPetSkillInstaller.install(
                    bundledSkillAt: source,
                    into: skillsRoot
                )
            ) { error in
                XCTAssertEqual(
                    error as? HatchPetSkillInstallerError,
                    .destinationAlreadyExists
                )
            }

            if existingKind == "directory" {
                XCTAssertEqual(
                    try Data(contentsOf: destination.appendingPathComponent("marker")),
                    Data("keep".utf8)
                )
                XCTAssertEqual(
                    HatchPetSkillInstaller.presence(in: skillsRoot),
                    .blockedByExistingEntry
                )
            } else {
                XCTAssertEqual(
                    HatchPetSkillInstaller.presence(in: skillsRoot),
                    .blockedByExistingEntry
                )
            }
        }
    }

    func testPresenceRequiresARegularSkillManifest() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let skillsRoot = base.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: false)
        let destination = HatchPetSkillInstaller.destinationURL(in: skillsRoot)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        XCTAssertEqual(
            HatchPetSkillInstaller.presence(in: skillsRoot),
            .blockedByExistingEntry
        )

        let externalManifest = base.appendingPathComponent("external-SKILL.md")
        try Data("external".utf8).write(to: externalManifest)
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("SKILL.md"),
            withDestinationURL: externalManifest
        )
        XCTAssertEqual(
            HatchPetSkillInstaller.presence(in: skillsRoot),
            .blockedByExistingEntry
        )

        try FileManager.default.removeItem(at: destination.appendingPathComponent("SKILL.md"))
        try Data("---\nname: hatch-pet\n---\n".utf8).write(
            to: destination.appendingPathComponent("SKILL.md")
        )
        XCTAssertEqual(HatchPetSkillInstaller.presence(in: skillsRoot), .installed)
    }

    func testRejectsSymlinkedSourceAndNestedSymlink() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try makeBundledSkill(in: base)
        let codexRoot = base.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: false)
        let skillsRoot = codexRoot.appendingPathComponent("skills", isDirectory: true)

        let linkedSource = base.appendingPathComponent("linked-source", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedSource, withDestinationURL: source)
        assertInstallThrows(
            .invalidBundledSource,
            source: linkedSource,
            skillsRoot: skillsRoot
        )

        let external = base.appendingPathComponent("external.py")
        try Data("print('external')".utf8).write(to: external)
        let unsafeSource = try makeBundledSkill(named: "unsafe", in: base)
        try FileManager.default.createSymbolicLink(
            at: unsafeSource.appendingPathComponent("scripts/linked.py"),
            withDestinationURL: external
        )
        assertInstallThrows(
            .unsafeBundledResource("scripts/linked.py"),
            source: unsafeSource,
            skillsRoot: skillsRoot
        )
        XCTAssertEqual(HatchPetSkillInstaller.presence(in: skillsRoot), .missing)
    }

    func testRejectsMissingRequiredResourcesAndUnsafeSkillsRoot() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try makeBundledSkill(in: base)
        try FileManager.default.removeItem(at: source.appendingPathComponent("LICENSE.txt"))

        let codexRoot = base.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: false)
        let skillsRoot = codexRoot.appendingPathComponent("skills", isDirectory: true)
        assertInstallThrows(
            .missingRequiredResource("LICENSE.txt"),
            source: source,
            skillsRoot: skillsRoot
        )

        let validSource = try makeBundledSkill(named: "valid", in: base)
        let realSkills = base.appendingPathComponent("real-skills", isDirectory: true)
        try FileManager.default.createDirectory(at: realSkills, withIntermediateDirectories: false)
        let linkedSkills = codexRoot.appendingPathComponent("linked-skills", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedSkills,
            withDestinationURL: realSkills
        )
        assertInstallThrows(
            .invalidSkillsRoot,
            source: validSource,
            skillsRoot: linkedSkills
        )
    }

    func testCleansOnlyItsPrivateStagingDirectoryAfterCopyFailure() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = try makeBundledSkill(in: base)
        let unreadable = source.appendingPathComponent("scripts/prepare_pet_run.py")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: unreadable.path
        )

        let codexRoot = base.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: false)
        let skillsRoot = codexRoot.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: false)
        let unrelated = skillsRoot.appendingPathComponent(
            ".hatch-pet-install-preserve",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: unrelated.appendingPathComponent("marker"))

        XCTAssertThrowsError(
            try HatchPetSkillInstaller.install(
                bundledSkillAt: source,
                into: skillsRoot
            )
        )

        XCTAssertEqual(try childNames(of: skillsRoot), [".hatch-pet-install-preserve"])
        XCTAssertEqual(
            try Data(contentsOf: unrelated.appendingPathComponent("marker")),
            Data("keep".utf8)
        )
    }

    private func makeBundledSkill(
        named name: String = "bundled-hatch-pet",
        in base: URL
    ) throws -> URL {
        let root = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("---\nname: hatch-pet\n---\n".utf8).write(
            to: root.appendingPathComponent("SKILL.md")
        )
        try Data("Apache License fixture".utf8).write(
            to: root.appendingPathComponent("LICENSE.txt")
        )

        let agents = root.appendingPathComponent("agents", isDirectory: true)
        let references = root.appendingPathComponent("references", isDirectory: true)
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        for directory in [agents, references, scripts] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
        }
        try Data("interface: Codex".utf8).write(
            to: agents.appendingPathComponent("openai.yaml")
        )
        try Data("8x11".utf8).write(
            to: references.appendingPathComponent("animation-rows.md")
        )
        try Data("print('prepare')\n".utf8).write(
            to: scripts.appendingPathComponent("prepare_pet_run.py")
        )
        return root
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HatchPetSkillInstallerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func childNames(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func assertInstallThrows(
        _ expected: HatchPetSkillInstallerError,
        source: URL,
        skillsRoot: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try HatchPetSkillInstaller.install(
                bundledSkillAt: source,
                into: skillsRoot
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? HatchPetSkillInstallerError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
