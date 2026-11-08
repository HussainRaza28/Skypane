//
//  WindowTracker.swift
//  Skypane
//

import AppKit
import CoreGraphics
import os

/// A normal app window as reported by the window server.
struct TrackedWindow {
    let windowNumber: Int
    let ownerProcessID: pid_t
    /// Bounds in CoreGraphics global coordinates (top-left origin of the primary display, y pointing down).
    let bounds: CGRect
}

/// Reads on-screen app window positions. Only bounds, layer, PID, and window number are used,
/// so no Screen Recording permission is needed.
final class WindowTracker {
    /// Windows smaller than this are ignored (invisible helper windows, tiny panels).
    private let minimumWindowSize = CGSize(width: 50, height: 30)

    /// The window layer used by normal app windows.
    private let normalWindowLayer = 0

    private let ownProcessID = ProcessInfo.processInfo.processIdentifier
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skypane", category: "WindowTracker")
    private var hasLoggedEmptyWindowList = false

    /// Returns visible app windows, ordered front to back.
    func currentWindows() -> [TrackedWindow] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            logEmptyWindowListOnce()
            return []
        }

        var trackedWindows: [TrackedWindow] = []
        trackedWindows.reserveCapacity(windowInfoList.count)

        for windowInfo in windowInfoList {
            guard
                let layer = windowInfo[kCGWindowLayer as String] as? Int, layer == normalWindowLayer,
                let ownerProcessID = windowInfo[kCGWindowOwnerPID as String] as? Int,
                pid_t(ownerProcessID) != ownProcessID,
                let windowNumber = windowInfo[kCGWindowNumber as String] as? Int,
                let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width >= minimumWindowSize.width,
                bounds.height >= minimumWindowSize.height
            else { continue }

            trackedWindows.append(TrackedWindow(
                windowNumber: windowNumber,
                ownerProcessID: pid_t(ownerProcessID),
                bounds: bounds
            ))
        }

        if trackedWindows.isEmpty {
            logEmptyWindowListOnce()
        }
        return trackedWindows
    }

    /// Notes once that no app windows were reported, which can mean window info is being withheld.
    private func logEmptyWindowListOnce() {
        guard !hasLoggedEmptyWindowList else { return }
        hasLoggedEmptyWindowList = true
        logger.warning("Window server returned no app windows; snow will not pile on windows.")
    }
}
