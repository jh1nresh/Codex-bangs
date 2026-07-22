import AppKit
import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

public struct EphemeralScreenCapture: Equatable, Sendable {
    public let fileURL: URL
    private let containingDirectory: URL

    init(fileURL: URL, containingDirectory: URL) {
        self.fileURL = fileURL
        self.containingDirectory = containingDirectory
    }

    public func remove(fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: containingDirectory)
    }
}

public enum ScreenCaptureServiceError: Error, Equatable, Sendable {
    case permissionDenied
    case noDisplayAvailable
    case captureFailed
    case encodingFailed
    case storageFailed
}

public struct ScreenCaptureService: Sendable {
    private static let maximumPixelDimension = 2_560
    private let temporaryRoot: URL

    public init(
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) {
        self.temporaryRoot = temporaryRoot
    }

    public func captureDisplayUnderPointer() async throws -> EphemeralScreenCapture {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenCaptureServiceError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ScreenCaptureServiceError.captureFailed
        }

        guard let display = selectedDisplay(from: content.displays) else {
            throw ScreenCaptureServiceError.noDisplayAvailable
        }

        let excludedApplications = content.applications.filter { application in
            application.bundleIdentifier == Bundle.main.bundleIdentifier
                || application.bundleIdentifier == "io.jeezlabs.CodexBangs"
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        let dimensions = Self.scaledDimensions(
            width: display.width,
            height: display.height
        )
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw ScreenCaptureServiceError.captureFailed
        }

        let representation = NSBitmapImageRep(cgImage: image)
        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw ScreenCaptureServiceError.encodingFailed
        }
        return try storePNGData(pngData)
    }

    func storePNGData(_ data: Data) throws -> EphemeralScreenCapture {
        let fileManager = FileManager.default
        let directory = temporaryRoot
            .appendingPathComponent(
                "CodexBangs-ScreenCapture-\(UUID().uuidString)",
                isDirectory: true
            )
        let fileURL = directory.appendingPathComponent("screen.png", isDirectory: false)

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try data.write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return EphemeralScreenCapture(
                fileURL: fileURL,
                containingDirectory: directory
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw ScreenCaptureServiceError.storageFailed
        }
    }

    private func selectedDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let screenNumber = screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber

        if let displayID = screenNumber?.uint32Value,
           let match = displays.first(where: { $0.displayID == displayID }) {
            return match
        }
        return displays.first
    }

    static func scaledDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        let longestEdge = max(width, height)
        guard longestEdge > maximumPixelDimension else {
            return (max(width, 1), max(height, 1))
        }

        let scale = Double(maximumPixelDimension) / Double(longestEdge)
        return (
            max(Int((Double(width) * scale).rounded()), 1),
            max(Int((Double(height) * scale).rounded()), 1)
        )
    }
}
