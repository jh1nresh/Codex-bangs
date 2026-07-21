import Darwin
import Foundation
import XCTest
@testable import CodexNotchPetCore

final class CodexExecutableLocatorTests: XCTestCase {
    func testBrokenAndNonOperationalCandidatesAreSkipped() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let broken = root.appendingPathComponent("broken", isDirectory: true)
        let stale = root.appendingPathComponent("stale", isDirectory: true)
        let impostor = root.appendingPathComponent("impostor", isDirectory: true)
        let valid = root.appendingPathComponent("valid", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: impostor, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createSymbolicLink(
            at: broken.appendingPathComponent("codex"),
            withDestinationURL: root.appendingPathComponent("missing-codex")
        )

        let staleExecutable = stale.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: staleExecutable)
        XCTAssertEqual(chmod(staleExecutable.path, 0o755), 0)

        let impostorExecutable = impostor.appendingPathComponent("codex")
        try Data("#!/bin/sh\nprintf 'unrelated-tool 1.0\\n'\n".utf8)
            .write(to: impostorExecutable)
        XCTAssertEqual(chmod(impostorExecutable.path, 0o755), 0)

        let executable = valid.appendingPathComponent("codex")
        try Data("#!/bin/sh\nprintf 'codex-cli test\\n'\nexit 0\n".utf8).write(to: executable)
        XCTAssertEqual(chmod(executable.path, 0o755), 0)

        let located = CodexExecutableLocator.locate(
            bundledPaths: [],
            environment: [
                "PATH": "\(broken.path):\(stale.path):\(impostor.path):\(valid.path)"
            ]
        )
        XCTAssertEqual(located?.path, executable.path)
    }
}
