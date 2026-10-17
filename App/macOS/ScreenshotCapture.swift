//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import AppKit
import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Screenshots for quick capture (PRD C5) with ScreenCaptureKit. Laterwise's own
/// windows are left out, so the capture panel never appears in the picture.
/// Screen Recording permission is requested the first time the user asks for one.
enum ScreenshotCapture {
    enum Failure: LocalizedError {
        case permissionNeeded
        case noDisplay
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .permissionNeeded:
                String(localized: "Allow Laterwise under Screen & System Audio Recording in System Settings, then try again.")
            case .noDisplay:
                String(localized: "No display to capture.")
            case .encodingFailed:
                String(localized: "The screenshot couldn't be saved.")
            }
        }
    }

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    /// The display under the pointer, where the user is looking.
    @MainActor
    static func displayUnderPointer() -> CGDirectDisplayID {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number?.uint32Value ?? CGMainDisplayID()
    }

    /// A PNG of the whole display, at full resolution.
    static func capturePNG(of displayID: CGDirectDisplayID) async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()      // shows the system prompt once
            throw Failure.permissionNeeded
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw Failure.noDisplay
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let mode = CGDisplayCopyDisplayMode(display.displayID)
        configuration.width = mode?.pixelWidth ?? display.width
        configuration.height = mode?.pixelHeight ?? display.height
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return try pngData(from: image)
    }

    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }
}
