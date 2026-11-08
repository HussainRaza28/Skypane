//
//  DockEstimator.swift
//  Skypane
//

import AppKit
import os

/// Estimates where the Dock is. macOS doesn't publish the Dock's size, so this combines the space the
/// Dock reserves at the bottom of the screen (its height) with its icon size and icon count from the
/// Dock's own preferences (its width). With optional Accessibility permission it reads the Dock's
/// exact frame instead. Only a Dock along the bottom edge is supported.
final class DockEstimator {
    /// Horizontal space per icon, relative to the icon size.
    private let tilePitchFactor: CGFloat = 1.04
    /// Width of each divider between Dock sections.
    private let separatorWidth: CGFloat = 14
    /// Space between the outermost icons and the ends of the Dock.
    private let endPadding: CGFloat = 10
    /// Gap between the top of the Dock and the bottom of the usable screen area.
    private let topGap: CGFloat = 5
    /// Reserved bottom space smaller than this means the Dock is hidden.
    private let minimumDockHeight: CGFloat = 20

    private let finderBundleIdentifier = "com.apple.finder"
    private let dockPreferences = UserDefaults(suiteName: "com.apple.dock")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skypane", category: "Dock")
    private var hasLoggedEstimate = false

    /// Whether Skypane has Accessibility permission, which lets it read the Dock's exact frame.
    var canMeasureDockExactly: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Accessibility settings. Granting it is optional;
    /// without it, the Dock's width is estimated.
    func requestExactDockMeasurement() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The Dock's frame in Cocoa global coordinates, or nil if it's hidden or not at the bottom.
    /// Exact when Accessibility permission is granted, estimated otherwise.
    func estimatedDockFrame() -> CGRect? {
        for screen in NSScreen.screens {
            let screenFrame = screen.frame
            let reservedBottomSpace = screen.visibleFrame.minY - screenFrame.minY
            guard reservedBottomSpace >= minimumDockHeight else { continue }

            if let measuredFrame = measuredDockFrame(), measuredFrame.intersects(screenFrame) {
                return measuredFrame
            }

            let dockTop = screen.visibleFrame.minY - topGap
            let dockWidth = min(estimatedDockWidth(reservedHeight: reservedBottomSpace), screenFrame.width)
            let dockFrame = CGRect(
                x: screenFrame.midX - dockWidth / 2,
                y: screenFrame.minY,
                width: dockWidth,
                height: dockTop - screenFrame.minY
            )

            if !hasLoggedEstimate {
                hasLoggedEstimate = true
                logger.info("Estimated Dock frame: \(String(describing: dockFrame), privacy: .public)")
            }
            return dockFrame
        }
        return nil
    }

    /// Reads the Dock's icon strip through Accessibility, which includes minimized windows and magnification.
    /// Returns nil without permission, or if the Dock isn't a horizontal strip.
    private func measuredDockFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }

        let dockElement = AXUIElementCreateApplication(dockApp.processIdentifier)
        // Don't let a busy Dock stall the main thread.
        AXUIElementSetMessagingTimeout(dockElement, 0.25)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let dockChildren = childrenValue as? [AXUIElement]
        else { return nil }

        // The icon strip is the Dock's list element.
        for dockChild in dockChildren where Self.role(of: dockChild) == kAXListRole as String {
            guard let position = Self.pointAttribute(kAXPositionAttribute, of: dockChild),
                  let size = Self.sizeAttribute(kAXSizeAttribute, of: dockChild),
                  size.width > size.height
            else { continue }

            // Accessibility uses top-left-origin global coordinates, like CoreGraphics.
            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
            return CGRect(
                x: position.x,
                y: primaryScreenHeight - (position.y + size.height),
                width: size.width,
                height: size.height
            )
        }
        return nil
    }

    private static func role(of element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success else { return nil }
        return roleValue as? String
    }

    private static func pointAttribute(_ attribute: String, of element: AXUIElement) -> CGPoint? {
        var attributeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &attributeValue) == .success,
              let attributeValue, CFGetTypeID(attributeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(attributeValue as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(_ attribute: String, of element: AXUIElement) -> CGSize? {
        var attributeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &attributeValue) == .success,
              let attributeValue, CFGetTypeID(attributeValue) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(attributeValue as! AXValue, .cgSize, &size) ? size : nil
    }

    /// Adds up the Dock's icons (Finder, pinned apps, other running apps, recent apps, pinned folders, and the Trash).
    private func estimatedDockWidth(reservedHeight: CGFloat) -> CGFloat {
        let iconSize = (dockPreferences?.object(forKey: "tilesize") as? Double).map { CGFloat($0) }
            ?? max(reservedHeight - 20, 16)

        let pinnedApps = dockPreferences?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        let pinnedBundleIdentifiers = Set(pinnedApps.compactMap(Self.bundleIdentifier(ofTile:)))
        let pinnedOtherCount = dockPreferences?.array(forKey: "persistent-others")?.count ?? 0

        // Running apps that aren't pinned still get an icon.
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningBundleIdentifiers = Set(runningApps.compactMap(\.bundleIdentifier))
        let unpinnedRunningCount = runningApps.filter { runningApp in
            guard let bundleIdentifier = runningApp.bundleIdentifier else { return true }
            return bundleIdentifier != finderBundleIdentifier && !pinnedBundleIdentifiers.contains(bundleIdentifier)
        }.count

        // Recent apps that aren't already shown, if the recents section is on.
        let showsRecentApps = dockPreferences?.object(forKey: "show-recents") as? Bool ?? true
        let recentApps = dockPreferences?.array(forKey: "recent-apps") as? [[String: Any]] ?? []
        let recentOnlyCount = showsRecentApps
            ? recentApps.compactMap(Self.bundleIdentifier(ofTile:)).filter {
                !runningBundleIdentifiers.contains($0) && !pinnedBundleIdentifiers.contains($0)
            }.count
            : 0

        let iconCount = 1 + pinnedApps.count + unpinnedRunningCount + recentOnlyCount + pinnedOtherCount + 1
        let separatorCount = (unpinnedRunningCount + recentOnlyCount > 0 ? 1 : 0) + 1

        return CGFloat(iconCount) * iconSize * tilePitchFactor
            + CGFloat(separatorCount) * separatorWidth
            + endPadding * 2
    }

    private nonisolated static func bundleIdentifier(ofTile tile: [String: Any]) -> String? {
        (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
    }
}
