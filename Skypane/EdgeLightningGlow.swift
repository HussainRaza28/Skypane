//
//  EdgeLightningGlow.swift
//  Skypane
//

import AppKit
import SpriteKit

/// A glow along the screen edges during lightning, drawn above app windows.
/// Each strike lights one random edge more brightly, as if it came from that side.
final class EdgeLightningGlow {
    /// Add this to the scene; it holds the four edge glows.
    let containerNode = SKNode()

    /// How far the glow reaches in from each edge.
    private let glowDepth: CGFloat = 90
    private let baseBrightnessScale: CGFloat = 1.2
    private let emphasizedBrightnessScale: CGFloat = 2.6

    /// Bottom, top, left, right.
    private var edgeSprites: [SKSpriteNode] = []
    private var emphasizedEdgeIndex = 0
    private var previousBrightness: CGFloat = 0

    init() {
        for _ in 0..<4 {
            let edgeSprite = SKSpriteNode(texture: WeatherTextures.edgeGlow)
            edgeSprite.color = NSColor(calibratedRed: 0.85, green: 0.9, blue: 1.0, alpha: 1)
            edgeSprite.colorBlendFactor = 1
            edgeSprite.anchorPoint = CGPoint(x: 0.5, y: 0)   // The bright end sits on the edge.
            edgeSprite.alpha = 0
            edgeSprite.isHidden = true
            containerNode.addChild(edgeSprite)
            edgeSprites.append(edgeSprite)
        }
    }

    /// Positions each glow along its edge, rotated so it fades toward the middle of the screen.
    func layOut(sceneSize: CGSize) {
        let width = sceneSize.width
        let height = sceneSize.height
        let placements: [(position: CGPoint, length: CGFloat, rotation: CGFloat)] = [
            (CGPoint(x: width / 2, y: 0), width, 0),               // Bottom
            (CGPoint(x: width / 2, y: height), width, .pi),        // Top
            (CGPoint(x: 0, y: height / 2), height, -.pi / 2),      // Left
            (CGPoint(x: width, y: height / 2), height, .pi / 2),   // Right
        ]
        for (edgeSprite, placement) in zip(edgeSprites, placements) {
            edgeSprite.position = placement.position
            edgeSprite.size = CGSize(width: placement.length, height: glowDepth)
            edgeSprite.zRotation = placement.rotation
        }
    }

    /// Whether a flash is lighting the edges right now.
    var isGlowing: Bool { previousBrightness > 0 }

    /// Matches the glow to the lightning flash on the desktop (0 when there's no flash).
    func setBrightness(_ brightness: CGFloat) {
        // A new strike picks which edge it comes from.
        if previousBrightness == 0, brightness > 0 {
            emphasizedEdgeIndex = Int.random(in: 0..<edgeSprites.count)
        }
        previousBrightness = brightness

        for (edgeIndex, edgeSprite) in edgeSprites.enumerated() {
            let scale = edgeIndex == emphasizedEdgeIndex ? emphasizedBrightnessScale : baseBrightnessScale
            edgeSprite.alpha = min(brightness * scale, 1)
            edgeSprite.isHidden = brightness <= 0
        }
    }
}
