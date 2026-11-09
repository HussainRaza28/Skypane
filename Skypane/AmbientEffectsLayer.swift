//
//  AmbientEffectsLayer.swift
//  Skypane
//

import AppKit
import SpriteKit

/// Decorative effects over the desktop: leaves, petals, confetti, fireflies, embers, bubbles,
/// stars, dust, shooting stars, and auroras. Each active kind has a reusable pool of sprites
/// that fades in and out as scenes change. Any mix of kinds can show at once.
final class AmbientEffectsLayer {
    /// Simulation state for one sprite. The meaning of the phases depends on the kind
    /// (sway for falling things, twinkle for stars, blink for fireflies).
    private struct Particle {
        var isActive = false
        var position: CGPoint = .zero
        var velocity: CGVector = .zero
        var baseX: CGFloat = 0
        var phase: CGFloat = 0
        var phaseRate: CGFloat = 0
        var swayAmplitude: CGFloat = 0
        var flipPhase: CGFloat = 0
        var flipRate: CGFloat = 0
        var spinRate: CGFloat = 0
        var age: CGFloat = 0
        /// Seconds for shooting stars; the height to stop at for embers and bubbles.
        var limit: CGFloat = 0
        var baseAlpha: CGFloat = 1
    }

    /// All the sprites for one kind of effect.
    private final class KindPool {
        let kind: AmbientKind
        let containerNode = SKNode()
        var particles: [Particle]
        var sprites: [SKSpriteNode] = []
        /// How many sprites should be showing.
        var targetCount = 0
        /// The layer's amount, used for aurora brightness and shooting-star frequency.
        var amount: CGFloat = 0
        var color: NSColor?
        /// Eases toward 1 while the kind is in the scene and toward 0 after it's removed.
        var visibility: CGFloat = 0
        var timeUntilNextShootingStar: CGFloat = 1

        init(kind: AmbientKind, capacity: Int) {
            self.kind = kind
            particles = Array(repeating: Particle(), count: capacity)
        }
    }

    /// Add this to the scene; it holds every effect.
    let containerNode = SKNode()

    /// How quickly effects fade in or out when the scene changes (fraction per second).
    private let fadeRate: CGFloat = 0.6

    private var pools: [KindPool] = []
    private var sceneSize: CGSize = .zero

    private func preparePools(for layers: [AmbientLayer]) {
        for kind in AmbientKind.allCases where layers.contains(where: { $0.kind == kind }) && !pools.contains(where: { $0.kind == kind }) {
            let pool = KindPool(kind: kind, capacity: Self.capacity(of: kind))
            pool.containerNode.isHidden = true
            pool.containerNode.alpha = 0
            containerNode.addChild(pool.containerNode)

            for index in 0..<pool.particles.count {
                let sprite = SKSpriteNode(texture: Self.texture(for: kind, index: index))
                sprite.isHidden = true
                if Self.glows(kind) {
                    sprite.blendMode = .add   // Glowing effects brighten what's behind them.
                }
                pool.containerNode.addChild(sprite)
                pool.sprites.append(sprite)
            }
            pools.append(pool)
        }
    }

    // MARK: - Configuration

    func layOut(sceneSize: CGSize) {
        self.sceneSize = sceneSize
    }

    /// Shows the given effects and fades out any others.
    func apply(_ layers: [AmbientLayer]) {
        preparePools(for: layers)
        for pool in pools {
            guard let layer = layers.first(where: { $0.kind == pool.kind }) else {
                pool.targetCount = 0
                continue
            }
            let amount = min(max(layer.amount, 0.15), 1)
            pool.amount = amount
            pool.targetCount = switch pool.kind {
            case .aurora, .shootingStars: pool.particles.count
            default: max(1, Int(CGFloat(pool.particles.count) * amount))
            }

            // Recolor anything already showing when the color changes.
            if pool.color != layer.color {
                pool.color = layer.color
                for index in pool.sprites.indices where pool.particles[index].isActive {
                    applyColor(to: pool.sprites[index], in: pool)
                }
            }
        }
    }

    /// Whether any effect is showing or still fading out.
    var isShowingAnything: Bool {
        pools.contains { $0.targetCount > 0 || $0.visibility >= 0.01 }
    }

    // MARK: - Per-frame update

    func update(deltaTime: CGFloat, windDrift: CGFloat) {
        // Retire pools only after their existing fade has finished.
        pools.removeAll { pool in
            guard pool.targetCount == 0, pool.visibility < 0.01 else { return false }
            pool.containerNode.removeFromParent()
            return true
        }
        for pool in pools {
            let targetVisibility: CGFloat = pool.targetCount > 0 ? 1 : 0
            pool.visibility += (targetVisibility - pool.visibility) * min(1, fadeRate * deltaTime)
            pool.containerNode.alpha = pool.visibility

            // Fully faded-out kinds cost nothing.
            if pool.targetCount == 0, pool.visibility < 0.01 {
                if !pool.containerNode.isHidden {
                    pool.containerNode.isHidden = true
                    for index in pool.particles.indices {
                        pool.particles[index].isActive = false
                        pool.sprites[index].isHidden = true
                    }
                }
                continue
            }
            pool.containerNode.isHidden = false

            if pool.kind == .shootingStars {
                launchShootingStarIfDue(in: pool, deltaTime: deltaTime)
            }
            for index in pool.particles.indices {
                updateParticle(at: index, in: pool, deltaTime: deltaTime, windDrift: windDrift)
            }
        }
    }

    private func updateParticle(at index: Int, in pool: KindPool, deltaTime: CGFloat, windDrift: CGFloat) {
        let isWanted = index < pool.targetCount
        guard pool.particles[index].isActive else {
            // Shooting stars launch on a timer instead of filling every slot.
            if isWanted, pool.kind != .shootingStars {
                spawnParticle(at: index, in: pool)
            }
            return
        }

        var particle = pool.particles[index]
        let sprite = pool.sprites[index]
        var isFinished = false
        particle.age += deltaTime

        switch pool.kind {
        case .leaves, .petals, .confetti:
            // Fall, drift with the wind, sway, spin, and flutter by squashing sideways.
            let windResponse: CGFloat = pool.kind == .petals ? 1.8 : (pool.kind == .leaves ? 1.5 : 1)
            particle.position.y -= particle.velocity.dy * deltaTime
            particle.baseX += particle.velocity.dy * windDrift * windResponse * deltaTime
            particle.phase += particle.phaseRate * deltaTime
            particle.flipPhase += particle.flipRate * deltaTime
            particle.position.x = particle.baseX + particle.swayAmplitude * sin(particle.phase)
            sprite.zRotation += particle.spinRate * deltaTime
            sprite.xScale = max(abs(cos(particle.flipPhase)), 0.15)
            isFinished = particle.position.y < -30
                || particle.position.x < -80 || particle.position.x > sceneSize.width + 80

        case .fireflies:
            updateFirefly(&particle, deltaTime: deltaTime)
            let pulse = max(sin(particle.phase), 0)
            sprite.alpha = pulse * pulse * pulse
            isFinished = !isWanted

        case .embers:
            // Rise, waver, flicker, and fade out as they climb.
            particle.position.y += particle.velocity.dy * deltaTime
            particle.phase += particle.phaseRate * deltaTime
            particle.baseX += windDrift * 30 * deltaTime
            particle.position.x = particle.baseX + particle.swayAmplitude * sin(particle.phase)
            let climb = min(max(particle.position.y / max(particle.limit, 1), 0), 1)
            let flicker = 0.75 + 0.25 * sin(particle.phase * 3.7)
            sprite.alpha = particle.baseAlpha * flicker * (1 - climb)
            isFinished = particle.position.y >= particle.limit

        case .bubbles:
            // Rise slowly with a wobble, then pop.
            particle.position.y += particle.velocity.dy * deltaTime
            particle.phase += particle.phaseRate * deltaTime
            particle.baseX += windDrift * 20 * deltaTime
            particle.position.x = particle.baseX + particle.swayAmplitude * sin(particle.phase)
            sprite.xScale = 1 + 0.06 * sin(particle.phase * 2)
            isFinished = particle.position.y >= particle.limit

        case .stars:
            particle.phase += particle.phaseRate * deltaTime
            sprite.alpha = particle.baseAlpha * (0.55 + 0.45 * sin(particle.phase))
            isFinished = !isWanted

        case .dust:
            // Drift slowly, nudged at random and by the wind, wrapping at the edges.
            particle.velocity.dx += CGFloat.random(in: -4...4) * deltaTime + windDrift * 4 * deltaTime
            particle.velocity.dy += CGFloat.random(in: -4...4) * deltaTime
            particle.velocity.dx = min(max(particle.velocity.dx, -14), 14)
            particle.velocity.dy = min(max(particle.velocity.dy, -10), 10)
            particle.position.x += particle.velocity.dx * deltaTime
            particle.position.y += particle.velocity.dy * deltaTime
            wrapInsideScene(&particle.position)
            particle.phase += particle.phaseRate * deltaTime
            sprite.alpha = particle.baseAlpha * (0.6 + 0.4 * sin(particle.phase))
            isFinished = !isWanted

        case .shootingStars:
            particle.position.x += particle.velocity.dx * deltaTime
            particle.position.y += particle.velocity.dy * deltaTime
            sprite.alpha = particle.baseAlpha * max(1 - particle.age / particle.limit, 0)
            isFinished = particle.age >= particle.limit

        case .aurora:
            // Ribbons drift side to side and slowly brighten and dim.
            particle.phase += particle.phaseRate * deltaTime
            particle.flipPhase += particle.flipRate * deltaTime
            particle.position.x = particle.baseX + particle.swayAmplitude * sin(particle.phase)
            sprite.alpha = particle.baseAlpha * (0.4 + 0.6 * pool.amount) * (0.6 + 0.4 * sin(particle.flipPhase))
            sprite.yScale = 1 + 0.12 * sin(particle.flipPhase * 0.7)
            isFinished = !isWanted
        }

        if isFinished {
            // Finished slots start over if still wanted; extras retire.
            if isWanted, pool.kind != .shootingStars {
                spawnParticle(at: index, in: pool, enteringScreen: true)
            } else {
                pool.particles[index].isActive = false
                sprite.isHidden = true
            }
            return
        }

        pool.particles[index] = particle
        sprite.position = particle.position
    }

    // MARK: - Spawning

    /// Starts a particle. Falling and rising kinds enter from off-screen once the effect is
    /// already showing; when it first fades in, they start spread across the screen.
    private func spawnParticle(at index: Int, in pool: KindPool, enteringScreen: Bool = false) {
        let width = max(sceneSize.width, 1)
        let height = max(sceneSize.height, 1)
        let startAnywhere = !enteringScreen && pool.visibility < 0.5
        let sprite = pool.sprites[index]
        var particle = Particle(isActive: true)
        var spriteSize = CGSize(width: 8, height: 8)
        sprite.zRotation = 0
        sprite.xScale = 1
        sprite.yScale = 1

        switch pool.kind {
        case .leaves, .petals, .confetti:
            let (speedRange, swayRange, periodRange, spinLimit, flipRange): (ClosedRange<CGFloat>, ClosedRange<CGFloat>, ClosedRange<CGFloat>, CGFloat, ClosedRange<CGFloat>) =
                switch pool.kind {
                case .leaves: (35...60, 30...60, 3...5, 1.5, 1.5...3.5)
                case .petals: (22...40, 20...45, 2.5...4.5, 1.2, 1...2.5)
                default: (60...110, 8...25, 1.5...3, 4, 4...9)
                }
            particle.baseX = CGFloat.random(in: -40...(width + 40))
            particle.position = CGPoint(
                x: particle.baseX,
                y: startAnywhere ? CGFloat.random(in: 0...height) : height + CGFloat.random(in: 20...(height * 0.5))
            )
            particle.velocity.dy = CGFloat.random(in: speedRange)
            particle.swayAmplitude = CGFloat.random(in: swayRange)
            particle.phase = CGFloat.random(in: 0...(2 * .pi))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: periodRange)
            particle.spinRate = CGFloat.random(in: -spinLimit...spinLimit)
            particle.flipPhase = CGFloat.random(in: 0...(2 * .pi))
            particle.flipRate = CGFloat.random(in: flipRange)
            particle.baseAlpha = CGFloat.random(in: 0.8...1)
            spriteSize = switch pool.kind {
            case .leaves: CGSize(width: CGFloat.random(in: 14...24), height: 0).squareFromWidth
            case .petals: CGSize(width: CGFloat.random(in: 8...13), height: 0).scaledHeight(1.3)
            default: CGSize(width: CGFloat.random(in: 5...8), height: 0).scaledHeight(1.5)
            }
            sprite.zRotation = CGFloat.random(in: 0...(2 * .pi))

        case .fireflies:
            particle.position = CGPoint(x: CGFloat.random(in: 0...width), y: CGFloat.random(in: 0...(height * 0.6)))
            particle.velocity = CGVector(dx: CGFloat.random(in: -10...10), dy: CGFloat.random(in: -10...10))
            particle.phase = CGFloat.random(in: 0...(2 * .pi))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 2...5)
            spriteSize = CGSize(width: CGFloat.random(in: 10...16), height: 0).squareFromWidth

        case .embers:
            particle.baseX = CGFloat.random(in: 0...width)
            particle.position = CGPoint(
                x: particle.baseX,
                y: startAnywhere ? CGFloat.random(in: 0...(height * 0.5)) : CGFloat.random(in: -20...0)
            )
            particle.velocity.dy = CGFloat.random(in: 40...90)
            particle.swayAmplitude = CGFloat.random(in: 6...15)
            particle.phase = CGFloat.random(in: 0...(2 * .pi))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 1.5...3)
            particle.limit = height * CGFloat.random(in: 0.4...0.75)
            particle.baseAlpha = CGFloat.random(in: 0.7...1)
            spriteSize = CGSize(width: CGFloat.random(in: 3...7), height: 0).squareFromWidth

        case .bubbles:
            particle.baseX = CGFloat.random(in: 0...width)
            particle.position = CGPoint(
                x: particle.baseX,
                y: startAnywhere ? CGFloat.random(in: 0...(height * 0.7)) : -30
            )
            particle.velocity.dy = CGFloat.random(in: 25...55)
            particle.swayAmplitude = CGFloat.random(in: 8...18)
            particle.phase = CGFloat.random(in: 0...(2 * .pi))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 2...4)
            particle.limit = height * CGFloat.random(in: 0.5...1.1)
            particle.baseAlpha = CGFloat.random(in: 0.55...0.85)
            spriteSize = CGSize(width: CGFloat.random(in: 10...28), height: 0).squareFromWidth

        case .stars:
            particle.position = CGPoint(x: CGFloat.random(in: 0...width), y: CGFloat.random(in: (height * 0.25)...height))
            particle.phase = CGFloat.random(in: 0...(2 * .pi))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 1.5...4)
            particle.baseAlpha = CGFloat.random(in: 0.5...1)
            spriteSize = CGSize(width: CGFloat.random(in: 1.5...4.5), height: 0).squareFromWidth

        case .dust:
            particle.position = CGPoint(x: CGFloat.random(in: 0...width), y: CGFloat.random(in: 0...height))
            particle.velocity = CGVector(dx: CGFloat.random(in: -6...6), dy: CGFloat.random(in: -6...6))
            particle.phase = CGFloat.random(in: 0...(2 * .pi))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 2...5)
            particle.baseAlpha = CGFloat.random(in: 0.2...0.45)
            spriteSize = CGSize(width: CGFloat.random(in: 2...4), height: 0).squareFromWidth

        case .shootingStars:
            // Streak diagonally down across the upper sky, leading with the bright end.
            let direction: CGFloat = Bool.random() ? 1 : -1
            let angleBelowHorizontal = CGFloat.random(in: 0.35...0.6)
            let speed = CGFloat.random(in: 700...1000)
            particle.position = CGPoint(x: CGFloat.random(in: (width * 0.1)...(width * 0.9)), y: height * CGFloat.random(in: 0.65...0.95))
            particle.velocity = CGVector(dx: direction * speed * cos(angleBelowHorizontal), dy: -speed * sin(angleBelowHorizontal))
            particle.limit = CGFloat.random(in: 0.5...0.8)
            particle.baseAlpha = 0.9
            sprite.zRotation = atan2(particle.velocity.dx, -particle.velocity.dy)
            spriteSize = CGSize(width: 2, height: CGFloat.random(in: 60...120))

        case .aurora:
            // Ribbons spread across the top of the screen.
            let slotCount = CGFloat(pool.particles.count)
            particle.baseX = width * (CGFloat(index) + 0.5) / slotCount + CGFloat.random(in: -60...60)
            particle.position = CGPoint(x: particle.baseX, y: height * CGFloat.random(in: 0.72...0.9))
            particle.swayAmplitude = CGFloat.random(in: 20...50)
            particle.phase = CGFloat.random(in: 0...(2 * .pi))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 20...30)
            particle.flipPhase = CGFloat.random(in: 0...(2 * .pi))
            particle.flipRate = 2 * .pi / CGFloat.random(in: 6...10)
            particle.baseAlpha = CGFloat.random(in: 0.35...0.55)
            spriteSize = CGSize(width: width * CGFloat.random(in: 0.5...0.75), height: height * CGFloat.random(in: 0.22...0.32))
        }

        pool.particles[index] = particle
        sprite.size = spriteSize
        sprite.position = particle.position
        sprite.alpha = particle.baseAlpha
        applyColor(to: sprite, in: pool)
        sprite.isHidden = false
    }

    /// Launches a shooting star every few seconds; more often for higher amounts.
    private func launchShootingStarIfDue(in pool: KindPool, deltaTime: CGFloat) {
        guard pool.targetCount > 0 else { return }
        pool.timeUntilNextShootingStar -= deltaTime
        guard pool.timeUntilNextShootingStar <= 0 else { return }

        let averageInterval = 6 - 4 * pool.amount
        pool.timeUntilNextShootingStar = CGFloat.random(in: (averageInterval * 0.5)...(averageInterval * 1.5))
        if let freeIndex = pool.particles.firstIndex(where: { !$0.isActive }) {
            spawnParticle(at: freeIndex, in: pool, enteringScreen: true)
        }
    }

    // MARK: - Helpers

    /// Wanders a firefly with small random nudges inside the lower part of the screen.
    private func updateFirefly(_ firefly: inout Particle, deltaTime: CGFloat) {
        let wanderTop = sceneSize.height * 0.6
        firefly.velocity.dx += CGFloat.random(in: -30...30) * deltaTime
        firefly.velocity.dy += CGFloat.random(in: -30...30) * deltaTime
        if firefly.position.x < 0 { firefly.velocity.dx += 20 * deltaTime }
        if firefly.position.x > sceneSize.width { firefly.velocity.dx -= 20 * deltaTime }
        if firefly.position.y < 0 { firefly.velocity.dy += 20 * deltaTime }
        if firefly.position.y > wanderTop { firefly.velocity.dy -= 20 * deltaTime }

        let speed = hypot(firefly.velocity.dx, firefly.velocity.dy)
        let maximumSpeed: CGFloat = 22
        if speed > maximumSpeed {
            firefly.velocity.dx *= maximumSpeed / speed
            firefly.velocity.dy *= maximumSpeed / speed
        }
        firefly.position.x += firefly.velocity.dx * deltaTime
        firefly.position.y += firefly.velocity.dy * deltaTime
        firefly.phase += firefly.phaseRate * deltaTime
    }

    private func wrapInsideScene(_ position: inout CGPoint) {
        if position.x < -10 { position.x = sceneSize.width + 10 }
        if position.x > sceneSize.width + 10 { position.x = -10 }
        if position.y < -10 { position.y = sceneSize.height + 10 }
        if position.y > sceneSize.height + 10 { position.y = -10 }
    }

    /// Colors a sprite with the scene's chosen color (varied slightly so it looks natural),
    /// or the kind's own colors when none was chosen.
    private func applyColor(to sprite: SKSpriteNode, in pool: KindPool) {
        if let chosenColor = pool.color {
            sprite.color = chosenColor.blended(withFraction: CGFloat.random(in: 0...0.2), of: .white) ?? chosenColor
            sprite.colorBlendFactor = 1
            return
        }
        guard let naturalColors = Self.naturalColors(for: pool.kind) else {
            sprite.colorBlendFactor = 0   // The texture already has the right colors.
            return
        }
        sprite.color = naturalColors[Int.random(in: 0..<naturalColors.count)]
        sprite.colorBlendFactor = 1
    }

    // MARK: - Per-kind constants

    private static func capacity(of kind: AmbientKind) -> Int {
        switch kind {
        case .leaves: 30
        case .petals: 40
        case .confetti: 60
        case .fireflies: 30
        case .embers: 45
        case .bubbles: 25
        case .stars: 90
        case .dust: 50
        case .shootingStars: 3
        case .aurora: 4
        }
    }

    private static func texture(for kind: AmbientKind, index: Int) -> SKTexture {
        switch kind {
        case .leaves: WeatherTextures.leaves[index % WeatherTextures.leaves.count]
        case .petals: WeatherTextures.petal
        case .confetti: WeatherTextures.confettiPiece
        case .fireflies, .embers: WeatherTextures.fireflyGlow
        case .bubbles: WeatherTextures.bubble
        case .stars, .dust: WeatherTextures.softFlake
        case .shootingStars: WeatherTextures.rainStreak
        case .aurora: WeatherTextures.auroraRibbon
        }
    }

    private static func glows(_ kind: AmbientKind) -> Bool {
        switch kind {
        case .fireflies, .embers, .stars, .dust, .shootingStars, .aurora: true
        case .leaves, .petals, .confetti, .bubbles: false
        }
    }

    /// Colors each kind uses when the scene doesn't choose one. Nil keeps the texture's own colors.
    private static func naturalColors(for kind: AmbientKind) -> [NSColor]? {
        switch kind {
        case .leaves:
            [NSColor(calibratedRed: 0.93, green: 0.45, blue: 0.13, alpha: 1),
             NSColor(calibratedRed: 0.80, green: 0.20, blue: 0.12, alpha: 1),
             NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.20, alpha: 1),
             NSColor(calibratedRed: 0.55, green: 0.32, blue: 0.16, alpha: 1)]
        case .petals:
            [NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.85, alpha: 1),
             NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.91, alpha: 1),
             NSColor(calibratedRed: 0.98, green: 0.70, blue: 0.80, alpha: 1)]
        case .confetti:
            [NSColor.systemPink, NSColor.systemYellow, NSColor.systemTeal,
             NSColor.systemPurple, NSColor.systemOrange, NSColor.systemGreen]
        case .embers:
            [NSColor(calibratedRed: 1.0, green: 0.5, blue: 0.15, alpha: 1),
             NSColor(calibratedRed: 1.0, green: 0.7, blue: 0.25, alpha: 1)]
        case .dust:
            [NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.8, alpha: 1)]
        case .aurora:
            [NSColor(calibratedRed: 0.3, green: 1.0, blue: 0.6, alpha: 1),
             NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.9, alpha: 1),
             NSColor(calibratedRed: 0.6, green: 0.4, blue: 1.0, alpha: 1)]
        case .fireflies, .bubbles, .stars, .shootingStars:
            nil
        }
    }
}

private extension CGSize {
    /// A square with this size's width.
    var squareFromWidth: CGSize { CGSize(width: width, height: width) }

    /// This width with a height that's a multiple of it.
    func scaledHeight(_ factor: CGFloat) -> CGSize { CGSize(width: width, height: width * factor) }
}
