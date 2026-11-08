//
//  SnowPileScene.swift
//  Skypane
//

import AppKit
import SpriteKit

/// An app window's frame in a scene's coordinate space (bottom-left origin).
struct SceneWindow {
    let windowNumber: Int
    let frame: CGRect
}

/// The front layer, drawn above app windows and the Dock: snow piled on window and Dock top edges,
/// chunks falling off, rain ripples on the Dock, and lightning on the screen edges.
final class SnowPileScene: SKScene, PrecipitationSurface, LightningObserver {
    /// Simulation state for one falling snow chunk.
    private struct FallingChunk {
        var position: CGPoint
        var velocity: CGVector
    }

    /// Stands in for a window number for the Dock's pile (real window numbers are positive).
    private static let dockPileNumber = -1

    /// Size of the reusable chunk pool.
    private let maximumChunkCount = 400
    /// Downward acceleration for falling chunks, in points per second squared.
    private let chunkGravity: CGFloat = 900
    /// How often changed piles are redrawn, so path rebuilding stays cheap.
    private let pileRedrawInterval: CGFloat = 1.0 / 20.0
    /// Frames within this distance count as unchanged, to ignore rounding noise.
    private let frameChangeTolerance: CGFloat = 0.5
    /// Largest simulation step, so a pause or hitch doesn't teleport chunks.
    private let maximumTimeStep: TimeInterval = 1.0 / 20.0
    /// How fast piles shrink when it's above freezing, in points per second (a full pile lasts a few minutes).
    private let meltRate: CGFloat = 0.05
    /// Bare space at each end of a pile: window corners, and the Dock's rounder corners.
    private let windowCornerInset: CGFloat = 10
    private let dockCornerInset: CGFloat = 20
    /// Fraction of raindrops hitting the Dock that leave a visible ripple.
    private let rippleChance = 0.35
    /// The cursor must move at least this fast (points per second) to brush snow, so a resting cursor doesn't.
    private let minimumBrushSpeed: CGFloat = 120
    private let brushRadius: CGFloat = 14
    /// How much of the cursor's velocity carries into brushed-off chunks.
    private let brushVelocityTransfer: CGFloat = 0.35

    /// Whether piles should slowly melt. Set from the current weather.
    var isMelting = false {
        didSet { wake() }
    }
    /// This screen's bottom-left corner in global coordinates, for converting the cursor position.
    var screenOrigin: CGPoint = .zero
    /// Whether sweeping the cursor brushes snow off piles. Set from the Settings window.
    var cursorInteracts = true {
        didSet {
            cursorMotion = CursorMotion()
            wake()
        }
    }

    /// Frame rates while something moves, and while the piles just sit there.
    private let activeFramesPerSecond = 60
    private let idleFramesPerSecond = 15
    /// How long to keep full speed after the last movement, and how long until drawing stops
    /// entirely when nothing can change.
    private let activityHoldDuration: CGFloat = 1
    private let sleepAfterIdleDuration: CGFloat = 3
    private var timeSinceLastActivity: CGFloat = 0

    /// Whether this screen's overlay is showing. The layer only wakes itself while it is.
    var allowsDrawing = true

    /// Piles keyed by window number, plus the same piles ordered front to back.
    private var pilesByWindowNumber: [Int: SnowPile] = [:]
    private var orderedPiles: [SnowPile] = []
    /// Piles whose windows went away, kept to reuse their shape nodes.
    private var reusablePiles: [SnowPile] = []

    /// The Dock's frame on this screen, or nil if it isn't here.
    private var dockFrame: CGRect?

    private var chunks: [FallingChunk] = []
    private var chunkSprites: [SKSpriteNode] = []
    private var isChunkActive: [Bool] = []
    private var freeChunkIndices: [Int] = []
    private var activeChunkCount = 0

    private let dockRipples = DockRipples()
    private let edgeLightning = EdgeLightningGlow()
    private var cursorMotion = CursorMotion()

    private var lastUpdateTime: TimeInterval?
    private var timeSinceLastPileRedraw: CGFloat = 0

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    override func didMove(to view: SKView) {
        guard chunkSprites.isEmpty else { return }

        // Piles use z 0–1; ripples, chunks, and lightning stack above them.
        dockRipples.containerNode.zPosition = 2
        edgeLightning.containerNode.zPosition = 5
        addChild(dockRipples.containerNode)
        addChild(edgeLightning.containerNode)
        edgeLightning.layOut(sceneSize: size)

        // Build the chunk pool once; chunks are recycled instead of created and destroyed.
        chunks.reserveCapacity(maximumChunkCount)
        chunkSprites.reserveCapacity(maximumChunkCount)
        isChunkActive.reserveCapacity(maximumChunkCount)
        freeChunkIndices.reserveCapacity(maximumChunkCount)

        for index in 0..<maximumChunkCount {
            let chunkSprite = SKSpriteNode(texture: WeatherTextures.flakeClumps[index % WeatherTextures.flakeClumps.count])
            chunkSprite.color = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1)
            chunkSprite.colorBlendFactor = 1
            chunkSprite.zPosition = 4
            chunkSprite.isHidden = true
            addChild(chunkSprite)

            chunkSprites.append(chunkSprite)
            chunks.append(FallingChunk(position: .zero, velocity: .zero))
            isChunkActive.append(false)
            freeChunkIndices.append(maximumChunkCount - 1 - index)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard !chunkSprites.isEmpty else { return }
        edgeLightning.layOut(sceneSize: size)
    }

    // MARK: - Window updates

    /// Syncs piles with the latest window list (ordered front to back) and the Dock's frame on this screen.
    /// Piles on windows that moved, resized, closed, or became covered fall off as chunks.
    func updateWindows(_ appWindows: [SceneWindow], dockFrame: CGRect?) {
        self.dockFrame = dockFrame

        // The Dock floats above app windows, so it goes first in front-to-back order.
        var sceneWindows = appWindows
        if let dockFrame {
            sceneWindows.insert(SceneWindow(windowNumber: Self.dockPileNumber, frame: dockFrame), at: 0)
        }

        var currentWindowNumbers = Set<Int>()
        orderedPiles.removeAll(keepingCapacity: true)

        for (windowIndex, sceneWindow) in sceneWindows.enumerated() {
            currentWindowNumbers.insert(sceneWindow.windowNumber)
            let existingPile = pilesByWindowNumber[sceneWindow.windowNumber]

            // Only windows whose top edge is on this screen can hold snow here.
            guard isTopEdgeOnScreen(sceneWindow.frame) else {
                if let existingPile { removePile(existingPile) }
                continue
            }

            let pile: SnowPile
            if let existingPile {
                pile = existingPile
                if !isSameFrame(pile.windowFrame, sceneWindow.frame) {
                    pile.refit(to: sceneWindow.frame) { x, height in
                        spawnChunk(atX: x, baseY: pile.edgeY, snowHeight: height)
                    }
                }
            } else {
                pile = makePile(for: sceneWindow)
            }

            // Only the parts of the top edge not covered by windows in front can hold snow.
            let windowsInFront = sceneWindows[..<windowIndex]
            let visibleSegments = visibleEdgeSegments(of: pile, windowsInFront: windowsInFront)
            pile.applyVisibleSegments(visibleSegments) { x, height in
                spawnChunk(atX: x, baseY: pile.edgeY, snowHeight: height)
            }

            orderedPiles.append(pile)
        }

        // Windows that closed, minimized, or left this Space (or a Dock that hid) drop their snow.
        for pile in Array(pilesByWindowNumber.values) where !currentWindowNumbers.contains(pile.windowNumber) {
            removePile(pile)
        }
    }

    /// Returns the horizontal ranges of a pile's top edge that no window in front overlaps.
    private func visibleEdgeSegments(of pile: SnowPile, windowsInFront: ArraySlice<SceneWindow>) -> [ClosedRange<CGFloat>] {
        guard let columnSpan = pile.columnSpan else { return [] }

        let clippedStart = max(columnSpan.lowerBound, 0)
        let clippedEnd = min(columnSpan.upperBound, size.width)
        guard clippedStart <= clippedEnd else { return [] }

        // The band above the edge where snow sits; a window overlapping it hides that part.
        let pileBandBottom = pile.edgeY
        let pileBandTop = pile.edgeY + SnowPile.maximumHeight

        var visibleSegments = [clippedStart...clippedEnd]
        for frontWindow in windowsInFront {
            let frontFrame = frontWindow.frame
            guard frontFrame.minY < pileBandTop, frontFrame.maxY > pileBandBottom else { continue }

            var remainingSegments: [ClosedRange<CGFloat>] = []
            for segment in visibleSegments {
                if frontFrame.maxX <= segment.lowerBound || frontFrame.minX >= segment.upperBound {
                    remainingSegments.append(segment)
                    continue
                }
                if frontFrame.minX > segment.lowerBound {
                    remainingSegments.append(segment.lowerBound...frontFrame.minX)
                }
                if frontFrame.maxX < segment.upperBound {
                    remainingSegments.append(frontFrame.maxX...segment.upperBound)
                }
            }
            visibleSegments = remainingSegments
        }
        return visibleSegments
    }

    private func isTopEdgeOnScreen(_ frame: CGRect) -> Bool {
        frame.maxY > 0 && frame.maxY < size.height && frame.maxX > 0 && frame.minX < size.width
    }

    private func isSameFrame(_ firstFrame: CGRect, _ secondFrame: CGRect) -> Bool {
        abs(firstFrame.minX - secondFrame.minX) < frameChangeTolerance
            && abs(firstFrame.minY - secondFrame.minY) < frameChangeTolerance
            && abs(firstFrame.width - secondFrame.width) < frameChangeTolerance
            && abs(firstFrame.height - secondFrame.height) < frameChangeTolerance
    }

    // MARK: - Pile lifecycle

    private func makePile(for sceneWindow: SceneWindow) -> SnowPile {
        let pile = reusablePiles.popLast()
            ?? SnowPile(windowNumber: sceneWindow.windowNumber, windowFrame: sceneWindow.frame)
        pile.cornerInset = sceneWindow.windowNumber == Self.dockPileNumber ? dockCornerInset : windowCornerInset
        pile.reset(windowNumber: sceneWindow.windowNumber, windowFrame: sceneWindow.frame)

        addChild(pile.shadowNode)
        addChild(pile.fillNode)
        wake()
        pilesByWindowNumber[sceneWindow.windowNumber] = pile
        return pile
    }

    /// Drops a pile's snow as chunks and sets the pile aside for reuse.
    private func removePile(_ pile: SnowPile) {
        pile.shedAllSnow { x, height in
            spawnChunk(atX: x, baseY: pile.edgeY, snowHeight: height)
        }
        pile.redrawIfNeeded()
        pile.shadowNode.removeFromParent()
        pile.fillNode.removeFromParent()
        pilesByWindowNumber[pile.windowNumber] = nil
        reusablePiles.append(pile)
    }

    // MARK: - Precipitation

    func catchFlake(atX x: CGFloat, fromY previousY: CGFloat, toY currentY: CGFloat, depositAmount: CGFloat) -> Bool {
        // Front to back, so the first pile hit is the one actually visible there.
        for pile in orderedPiles
        where pile.catchFlake(atX: x, fromY: previousY, toY: currentY, depositAmount: depositAmount) {
            wake()
            return true
        }
        return false
    }

    func catchRaindrop(atX x: CGFloat, fromY previousY: CGFloat, toY currentY: CGFloat) -> Bool {
        // Raindrops end on the top of the Dock, some with a visible ripple.
        guard let dockFrame,
              x > dockFrame.minX + dockCornerInset, x < dockFrame.maxX - dockCornerInset,
              previousY >= dockFrame.maxY, currentY < dockFrame.maxY
        else { return false }

        if Double.random(in: 0..<1) < rippleChance {
            dockRipples.spawnRipple(at: CGPoint(x: x, y: dockFrame.maxY + CGFloat.random(in: -1...2)))
            wake()
        }
        return true
    }

    // MARK: - Lightning

    func lightningBrightnessDidChange(_ brightness: CGFloat) {
        edgeLightning.setBrightness(brightness)
        if brightness > 0 {
            wake()
        }
    }

    /// Whether any window or the Dock has snow resting on it.
    var hasPiledSnow: Bool {
        orderedPiles.contains { $0.hasSnow }
    }

    /// Resumes drawing after the layer went to sleep.
    func wake() {
        timeSinceLastActivity = 0
        guard allowsDrawing, let view, view.isPaused else { return }
        lastUpdateTime = nil
        view.isPaused = false
    }

    // MARK: - Cursor brushing

    /// Knocks snow off piles where the cursor sweeps through quickly, flinging chunks along with it.
    private func brushSnow(with cursorMovement: CursorMotion.Movement) {
        guard cursorMovement.speed >= minimumBrushSpeed else { return }

        let push = CGVector(
            dx: cursorMovement.velocity.dx * brushVelocityTransfer,
            dy: max(cursorMovement.velocity.dy * brushVelocityTransfer, 0)
        )
        cursorMovement.forEachSample(spacing: 8, maximumSamples: 24) { point in
            for pile in orderedPiles where pile.isInSnowBand(point) {
                pile.brushSnow(aroundX: point.x, radius: brushRadius) { x, height in
                    spawnChunk(atX: x, baseY: pile.edgeY, snowHeight: height, push: push)
                }
            }
        }
    }

    // MARK: - Falling chunks

    /// Turns one heightmap column of snow into a falling chunk (about every other column, to keep counts low).
    /// `push` adds extra velocity, such as from the cursor.
    private func spawnChunk(atX x: CGFloat, baseY: CGFloat, snowHeight: CGFloat, push: CGVector = .zero) {
        guard snowHeight > 0.4, Bool.random(), let index = freeChunkIndices.popLast() else { return }

        // Soft textures fade at the edges, so chunks are drawn a bit larger than their visible size.
        let diameter = min(3 + snowHeight * 0.5, 9) * CGFloat.random(in: 0.7...1.2)
        let startPosition = CGPoint(
            x: x + CGFloat.random(in: -1...1),
            y: baseY + snowHeight * CGFloat.random(in: 0.2...0.9)
        )
        chunks[index] = FallingChunk(
            position: startPosition,
            velocity: CGVector(
                dx: CGFloat.random(in: -35...35) + push.dx * CGFloat.random(in: 0.6...1.2),
                dy: CGFloat.random(in: 0...70) + push.dy * CGFloat.random(in: 0.6...1.2)
            )
        )
        isChunkActive[index] = true
        activeChunkCount += 1
        wake()

        let chunkSprite = chunkSprites[index]
        chunkSprite.size = CGSize(width: diameter, height: diameter)
        chunkSprite.alpha = CGFloat.random(in: 0.85...1)
        chunkSprite.position = startPosition
        chunkSprite.isHidden = false
    }

    // MARK: - Per-frame update

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = CGFloat(min(currentTime - (lastUpdateTime ?? currentTime), maximumTimeStep))
        lastUpdateTime = currentTime
        guard deltaTime > 0 else { return }

        if cursorInteracts, let cursorMovement = cursorMotion.update(screenOrigin: screenOrigin, deltaTime: deltaTime) {
            brushSnow(with: cursorMovement)
        }

        if activeChunkCount > 0 {
            updateChunks(deltaTime: deltaTime)
        }

        if isMelting {
            for pile in orderedPiles {
                pile.melt(by: meltRate * deltaTime)
            }
        }

        dockRipples.update(deltaTime: deltaTime)

        // Redraw changed piles a few times a second rather than on every landing.
        timeSinceLastPileRedraw += deltaTime
        if timeSinceLastPileRedraw >= pileRedrawInterval {
            timeSinceLastPileRedraw = 0
            var didRedraw = false
            for pile in orderedPiles where pile.redrawIfNeeded() {
                didRedraw = true
            }
            if didRedraw {
                timeSinceLastActivity = 0
            }
        }
        updateFrameRate(deltaTime: deltaTime)
    }

    /// Draws at full speed while chunks fall, ripples spread, lightning glows, or piles change,
    /// and slowly while the piles just sit there, to save power.
    private func updateFrameRate(deltaTime: CGFloat) {
        let isMoving = activeChunkCount > 0 || dockRipples.hasActiveRipples || edgeLightning.isGlowing
        timeSinceLastActivity = isMoving ? 0 : timeSinceLastActivity + deltaTime
        let framesPerSecond = timeSinceLastActivity > activityHoldDuration ? idleFramesPerSecond : activeFramesPerSecond
        if let view, view.preferredFramesPerSecond != framesPerSecond {
            view.preferredFramesPerSecond = framesPerSecond
        }

        // Piled snow keeps the layer awake when the cursor can brush it or it's melting.
        if timeSinceLastActivity > sleepAfterIdleDuration, !(hasPiledSnow && (cursorInteracts || isMelting)) {
            view?.isPaused = true
        }
    }

    /// Moves chunks under gravity and returns ones that left the screen to the pool.
    private func updateChunks(deltaTime: CGFloat) {
        for index in chunks.indices where isChunkActive[index] {
            var chunk = chunks[index]
            chunk.velocity.dy -= chunkGravity * deltaTime
            chunk.position.x += chunk.velocity.dx * deltaTime
            chunk.position.y += chunk.velocity.dy * deltaTime

            let leftScreen = chunk.position.y < -10 || chunk.position.x < -20 || chunk.position.x > size.width + 20
            if leftScreen {
                isChunkActive[index] = false
                chunkSprites[index].isHidden = true
                freeChunkIndices.append(index)
                activeChunkCount -= 1
                continue
            }

            chunks[index] = chunk
            chunkSprites[index].position = chunk.position
        }
    }
}
