//
//  CursorMotion.swift
//  Skypane
//

import AppKit

/// Follows the cursor in one scene's coordinates. Reading the cursor position needs no permissions,
/// and the overlays stay click-through.
struct CursorMotion {
    /// The path the cursor covered since the previous frame, and how fast it moved.
    struct Movement {
        let start: CGPoint
        let end: CGPoint
        let velocity: CGVector

        var speed: CGFloat { hypot(velocity.dx, velocity.dy) }

        /// Calls `body` with evenly spaced points from start to end (at most `maximumSamples`), without allocating.
        func forEachSample(spacing: CGFloat, maximumSamples: Int, _ body: (CGPoint) -> Void) {
            let distance = hypot(end.x - start.x, end.y - start.y)
            let sampleCount = min(max(Int(distance / spacing), 1), maximumSamples)
            for sampleIndex in 0...sampleCount {
                let progress = CGFloat(sampleIndex) / CGFloat(sampleCount)
                body(CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress))
            }
        }
    }

    private var previousLocation: CGPoint?

    /// Reads the cursor and returns how it moved since the last call, or nil on the first call.
    /// `screenOrigin` is the screen's bottom-left corner in global coordinates.
    mutating func update(screenOrigin: CGPoint, deltaTime: CGFloat) -> Movement? {
        let globalLocation = NSEvent.mouseLocation
        let location = CGPoint(x: globalLocation.x - screenOrigin.x, y: globalLocation.y - screenOrigin.y)
        defer { previousLocation = location }

        guard let previousLocation, deltaTime > 0 else { return nil }
        let velocity = CGVector(
            dx: (location.x - previousLocation.x) / deltaTime,
            dy: (location.y - previousLocation.y) / deltaTime
        )
        return Movement(start: previousLocation, end: location, velocity: velocity)
    }
}
