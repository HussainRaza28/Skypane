//
//  DockRipples.swift
//  Skypane
//

import SpriteKit

/// Small expanding rings where raindrops hit the top of the Dock.
final class DockRipples {
    /// Add this to the scene; it holds every ripple sprite.
    let containerNode = SKNode()

    private let maximumRippleCount = 40
    /// Seconds for a ripple to spread out and fade.
    private let rippleDuration: CGFloat = 0.55
    private let startWidth: CGFloat = 4
    private let endWidth: CGFloat = 20
    private let startAlpha: CGFloat = 0.6

    private var rippleSprites: [SKSpriteNode] = []
    private var rippleAges: [CGFloat] = []
    private var isRippleActive: [Bool] = []
    private var activeRippleCount = 0

    /// Whether any ripple is still spreading.
    var hasActiveRipples: Bool { activeRippleCount > 0 }
    private var freeRippleIndices: [Int] = []

    init() {
        // Ripple pool, built once and reused.
        for index in 0..<maximumRippleCount {
            let rippleSprite = SKSpriteNode(texture: WeatherTextures.rippleRing)
            rippleSprite.isHidden = true
            containerNode.addChild(rippleSprite)
            rippleSprites.append(rippleSprite)
            rippleAges.append(0)
            isRippleActive.append(false)
            freeRippleIndices.append(maximumRippleCount - 1 - index)
        }
    }

    /// Starts a ripple at a point, if one is free.
    func spawnRipple(at position: CGPoint) {
        guard let index = freeRippleIndices.popLast() else { return }
        rippleAges[index] = 0
        isRippleActive[index] = true
        activeRippleCount += 1
        rippleSprites[index].position = position
        rippleSprites[index].isHidden = false
        applyAppearance(toRippleAt: index, progress: 0)
    }

    func update(deltaTime: CGFloat) {
        for index in rippleSprites.indices where isRippleActive[index] {
            rippleAges[index] += deltaTime
            let progress = rippleAges[index] / rippleDuration

            if progress >= 1 {
                isRippleActive[index] = false
                rippleSprites[index].isHidden = true
                freeRippleIndices.append(index)
                activeRippleCount -= 1
            } else {
                applyAppearance(toRippleAt: index, progress: progress)
            }
        }
    }

    /// Widens the ring (flattened, as if seen at an angle) and fades it out.
    private func applyAppearance(toRippleAt index: Int, progress: CGFloat) {
        let width = startWidth + (endWidth - startWidth) * progress
        rippleSprites[index].size = CGSize(width: width, height: width * 0.25)
        rippleSprites[index].alpha = startAlpha * (1 - progress)
    }
}
