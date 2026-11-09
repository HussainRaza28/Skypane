//
//  ScreenOverlay.swift
//  Skypane
//

import AppKit
import QuartzCore
import SpriteKit

/// The two click-through overlay windows covering one screen:
/// a back layer for weather (behind app windows) and a front layer for snow piles and falling chunks.
final class ScreenOverlay {
    /// Just above the desktop icons, so normal app windows cover the falling snow.
    private static let backLayerLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    /// Above app windows, so piles sit on top of them.
    private static let frontLayerLevel = NSWindow.Level.statusBar

    /// The screen's frame in Cocoa global coordinates (bottom-left origin of the primary display).
    private let screenFrame: CGRect
    /// Bottom of the menu bar in scene coordinates (the top of the usable screen area).
    private let usableAreaTopY: CGFloat

    private let backWindow: NSWindow
    private let frontWindow: NSWindow
    private let backView: SKView
    private let frontView: SKView
    private let weatherScene: WeatherScene
    private let pileScene: SnowPileScene

    init(screen: NSScreen) {
        screenFrame = screen.frame

        backWindow = Self.makeOverlayWindow(frame: screenFrame, level: Self.backLayerLevel)
        frontWindow = Self.makeOverlayWindow(frame: screenFrame, level: Self.frontLayerLevel)
        backView = Self.makeTransparentView(size: screenFrame.size)
        frontView = Self.makeTransparentView(size: screenFrame.size)

        // Falling snow and rain hit the piles and Dock held by the front scene,
        // and the front scene mirrors lightning on the screen edges.
        weatherScene = WeatherScene(size: screenFrame.size)
        pileScene = SnowPileScene(size: screenFrame.size)
        weatherScene.precipitationSurface = pileScene
        weatherScene.lightningObserver = pileScene

        // Both scenes follow the cursor, which is reported in global coordinates.
        weatherScene.screenOrigin = screenFrame.origin
        pileScene.screenOrigin = screenFrame.origin

        // Full-screen apps reach up to (or past) the bottom of the menu bar.
        let menuBarHeight = screenFrame.maxY - screen.visibleFrame.maxY
        usableAreaTopY = screenFrame.height - menuBarHeight

        backView.presentScene(weatherScene)
        frontView.presentScene(pileScene)
        backWindow.contentView = backView
        frontWindow.contentView = frontView

        // Each full-screen frame takes about 24 MB on a Retina screen. Two in flight is plenty at
        // these frame rates, and saves a frame's worth of memory per layer.
        for spriteView in [backView, frontView] {
            (spriteView.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        }

        backWindow.orderFrontRegardless()
        frontWindow.orderFrontRegardless()
    }

    /// Settings that change what this screen shows. Set by the app delegate.
    var pilesSnowOnWindows = true
    var showsDockEffects = true
    var pausesInFullScreen = true
    var cursorInteracts = true {
        didSet {
            weatherScene.cursorInteracts = cursorInteracts
            pileScene.cursorInteracts = cursorInteracts
        }
    }

    /// Reasons this screen's weather is paused. Any one of them hides both layers and stops drawing.
    private var isPausedByPerson = false
    private var isPausedForPower = false
    private var isPausedForFullScreen = false
    private var isShowingOverlays = true

    /// Converts tracked windows and the Dock (in Cocoa global coordinates) into this screen's
    /// scene coordinates and updates the piles.
    func updateTrackedWindows(_ trackedWindows: [TrackedWindow], dockFrame: CGRect?, primaryScreenHeight: CGFloat) {
        let sceneBounds = CGRect(origin: .zero, size: screenFrame.size)

        let sceneWindows: [SceneWindow] = trackedWindows.compactMap { trackedWindow in
            // CoreGraphics global (top-left origin, y down) to Cocoa global (bottom-left origin, y up).
            let bounds = trackedWindow.bounds
            let cocoaFrame = CGRect(
                x: bounds.minX,
                y: primaryScreenHeight - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
            // Cocoa global to this screen's scene coordinates.
            let sceneFrame = cocoaFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            guard sceneFrame.intersects(sceneBounds) else { return nil }
            return SceneWindow(windowNumber: trackedWindow.windowNumber, frame: sceneFrame)
        }

        // A full-screen app hides the Dock, and its window has no top edge to hold snow,
        // so both piles fall off while it's showing. Effects can also pause entirely.
        let isShowingFullScreenApp = sceneWindows.contains { isFullScreenFrame($0.frame) }
        isPausedForFullScreen = pausesInFullScreen && isShowingFullScreenApp
        updateVisibility()

        let pileableWindows: [SceneWindow] = if !pilesSnowOnWindows {
            []
        } else if isShowingFullScreenApp {
            sceneWindows.filter { !isFullScreenFrame($0.frame) }
        } else {
            sceneWindows
        }

        // The Dock only counts on the screen it's actually on, and only when it's showing.
        let sceneDockFrame = isShowingFullScreenApp || !showsDockEffects ? nil : dockFrame
            .map { $0.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY) }
            .flatMap { $0.intersects(sceneBounds) ? $0 : nil }

        pileScene.updateWindows(pileableWindows, dockFrame: sceneDockFrame)
    }

    /// Whether a window (in scene coordinates) fills the screen like a full-screen app: full width,
    /// from the bottom edge up to at least the menu bar. A zoomed window stops above the Dock, so it doesn't count.
    private func isFullScreenFrame(_ frame: CGRect) -> Bool {
        frame.minX <= 1
            && frame.maxX >= screenFrame.width - 1
            && frame.minY <= 1
            && frame.maxY >= usableAreaTopY - 1
    }

    /// Shows new weather on this screen.
    func apply(_ effect: WeatherEffect) {
        weatherScene.apply(effect)
        pileScene.isMelting = effect.isMelting
    }

    /// Updates the night and sunrise/sunset tint over the desktop.
    func apply(_ skyTint: SkyTint) {
        weatherScene.apply(skyTint)
    }

    /// Pauses or resumes this screen at the person's request (the menu's Pause Weather).
    func setPaused(_ isPaused: Bool) {
        isPausedByPerson = isPaused
        updateVisibility()
    }

    /// Pauses or resumes this screen to save power.
    func setPausedForPower(_ isPaused: Bool) {
        isPausedForPower = isPaused
        updateVisibility()
    }

    /// Hides both layers and stops drawing while any pause reason applies; shows them otherwise.
    private func updateVisibility() {
        let shouldShow = !isPausedByPerson && !isPausedForPower && !isPausedForFullScreen
        guard shouldShow != isShowingOverlays else { return }
        isShowingOverlays = shouldShow

        weatherScene.allowsDrawing = shouldShow
        pileScene.allowsDrawing = shouldShow
        backView.isPaused = !shouldShow
        frontView.isPaused = !shouldShow
        if shouldShow {
            weatherScene.wake()
            pileScene.wake()
        }
        for overlayWindow in [backWindow, frontWindow] {
            if shouldShow {
                overlayWindow.orderFrontRegardless()
            } else {
                overlayWindow.orderOut(nil)
            }
        }
    }

    /// Whether any window or the Dock on this screen has snow resting on it.
    var hasPiledSnow: Bool { pileScene.hasPiledSnow }

    /// Lets the sleeping pile layer know the cursor moved, so it can wake before a brush.
    func wakeIfCursorIsNearPiles(globalCursorLocation: CGPoint) {
        guard isShowingOverlays else { return }
        pileScene.wakeIfCursorIsNearPiles(globalCursorLocation: globalCursorLocation)
    }

    /// Removes both windows, for when this screen goes away or the screens are rearranged.
    func close() {
        weatherScene.allowsDrawing = false
        pileScene.allowsDrawing = false
        backView.isPaused = true
        frontView.isPaused = true
        backWindow.close()
        frontWindow.close()
    }

    /// Snapshot for benchmark validation; hidden or paused overlays must not count as active weather.
    var benchmarkState: [String: Any] {
        [
            "visible": isShowingOverlays,
            "weatherPaused": backView.isPaused,
            "pilesPaused": frontView.isPaused,
            "weatherFPS": backView.preferredFramesPerSecond,
            "pilesFPS": frontView.preferredFramesPerSecond
        ]
    }

    // MARK: - Setup helpers

    /// A borderless, transparent, click-through window that appears on every Space.
    private static func makeOverlayWindow(frame: CGRect, level: NSWindow.Level) -> NSWindow {
        let overlayWindow = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = level
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        overlayWindow.isReleasedWhenClosed = false
        overlayWindow.setFrame(frame, display: false)
        return overlayWindow
    }

    /// A transparent SpriteKit view capped at 60fps.
    private static func makeTransparentView(size: CGSize) -> SKView {
        let spriteView = SKView(frame: NSRect(origin: .zero, size: size))
        spriteView.allowsTransparency = true
        spriteView.ignoresSiblingOrder = true
        spriteView.preferredFramesPerSecond = 60
        spriteView.autoresizingMask = [.width, .height]
        return spriteView
    }
}
