//
//  CustomParticleLayer.swift
//  Skypane
//

import AppKit
import CoreImage
import SpriteKit

/// Draws anything that isn't a built-in effect as emoji particles, such as pink 🐉 falling or
/// 💖 floating up. Each of a few slots shows one emoji layer with its own color and motion,
/// using a fixed pool of sprites. Changing a slot's layer fades the old one out first.
final class CustomParticleLayer {
    private struct Particle {
        var isActive = false
        var position: CGPoint = .zero
        var velocity: CGVector = .zero
        var baseX: CGFloat = 0
        var baseY: CGFloat = 0
        var phase: CGFloat = 0
        var phaseRate: CGFloat = 0
        var swayAmplitude: CGFloat = 0
        var spinRate: CGFloat = 0
        /// The height a rising particle fades out at.
        var limit: CGFloat = 0
        var baseAlpha: CGFloat = 1
    }

    private final class Slot {
        let containerNode = SKNode()
        var particles: [Particle]
        var sprites: [SKSpriteNode] = []
        /// What the slot is showing, and what it should show next once the current layer has faded
        /// out. `hasPendingChange` is separate because the next layer can be "nothing".
        var layer: CustomLayer?
        var nextLayer: CustomLayer?
        var hasPendingChange = false
        var visibility: CGFloat = 0
        var targetCount = 0

        init(capacity: Int) {
            particles = Array(repeating: Particle(), count: capacity)
        }
    }

    /// Add this to the scene; it holds every emoji layer.
    let containerNode = SKNode()

    /// Most emoji layers that can show at once, and sprites per layer.
    static let maximumLayerCount = 4
    private let spritesPerLayer = 45
    /// How quickly layers fade in or out (fraction per second).
    private let fadeRate: CGFloat = 0.8

    private var slots: [Slot] = []
    private var sceneSize: CGSize = .zero
    /// Emoji textures, made once per emoji and color treatment and shared by every screen.
    private static let textureCache = NSMapTable<NSString, SKTexture>.strongToWeakObjects()
    private static let imageContext = CIContext()

    init() {
        for _ in 0..<Self.maximumLayerCount {
            let slot = Slot(capacity: 0)
            slot.containerNode.isHidden = true
            containerNode.addChild(slot.containerNode)
            slots.append(slot)
        }
    }

    func layOut(sceneSize: CGSize) {
        self.sceneSize = sceneSize
    }

    /// Shows these emoji layers. Unchanged layers keep going; changed ones fade over.
    func apply(_ layers: [CustomLayer]) {
        for (index, slot) in slots.enumerated() {
            let newLayer = index < layers.count ? layers[index] : nil
            if newLayer == slot.layer {
                slot.hasPendingChange = false
                slot.nextLayer = nil
            } else if slot.layer == nil || slot.visibility < 0.02 {
                slot.hasPendingChange = false
                start(newLayer, in: slot)
            } else {
                // Fade the current layer out; the new one (or nothing) starts once it's gone.
                slot.nextLayer = newLayer
                slot.hasPendingChange = true
            }
        }
    }

    /// Whether any emoji layer is showing or still fading out.
    var isShowingAnything: Bool {
        slots.contains { $0.layer != nil || $0.visibility >= 0.01 }
    }

    func update(deltaTime: CGFloat, windDrift: CGFloat) {
        for slot in slots {
            let targetVisibility: CGFloat = slot.layer != nil && !slot.hasPendingChange ? 1 : 0
            slot.visibility += (targetVisibility - slot.visibility) * min(1, fadeRate * deltaTime)
            slot.containerNode.alpha = slot.visibility

            if slot.hasPendingChange, slot.visibility < 0.02 {
                start(slot.nextLayer, in: slot)
                slot.nextLayer = nil
                slot.hasPendingChange = false
            }

            guard let layer = slot.layer else {
                slot.containerNode.isHidden = true
                continue
            }
            slot.containerNode.isHidden = slot.visibility < 0.01 && targetVisibility == 0
            guard !slot.containerNode.isHidden else { continue }

            for index in slot.particles.indices {
                updateParticle(at: index, in: slot, layer: layer, deltaTime: deltaTime, windDrift: windDrift)
            }
        }
    }

    // MARK: - Layers

    /// Switches a slot to a new layer (or empties it), retexturing every sprite.
    private func start(_ layer: CustomLayer?, in slot: Slot) {
        slot.layer = layer
        for index in slot.particles.indices {
            slot.particles[index].isActive = false
            slot.sprites[index].isHidden = true
        }
        guard let layer else {
            slot.targetCount = 0
            slot.containerNode.removeAllChildren()
            slot.sprites.removeAll()
            slot.particles.removeAll()
            return
        }
        if slot.sprites.isEmpty {
            slot.particles = Array(repeating: Particle(), count: spritesPerLayer)
            for _ in 0..<spritesPerLayer {
                let sprite = SKSpriteNode()
                sprite.isHidden = true
                slot.containerNode.addChild(sprite)
                slot.sprites.append(sprite)
            }
        }

        // Bigger emoji need fewer to fill the screen.
        let sizeFactor = min(max(28 / layer.size, 0.5), 1.6)
        slot.targetCount = min(spritesPerLayer, max(3, Int(26 * layer.amount * sizeFactor)))

        let texture = emojiTexture(for: layer.emoji, recolored: layer.color != nil)
        for sprite in slot.sprites {
            sprite.texture = texture
            sprite.color = layer.color ?? .white
            sprite.colorBlendFactor = layer.color == nil ? 0 : 1
        }
    }

    // MARK: - Motion

    private func updateParticle(at index: Int, in slot: Slot, layer: CustomLayer, deltaTime: CGFloat, windDrift: CGFloat) {
        let isWanted = index < slot.targetCount
        guard slot.particles[index].isActive else {
            if isWanted {
                spawnParticle(at: index, in: slot, layer: layer, enteringScreen: slot.visibility > 0.5)
            }
            return
        }

        var particle = slot.particles[index]
        let sprite = slot.sprites[index]
        let width = sceneSize.width
        var isFinished = false
        particle.phase += particle.phaseRate * deltaTime

        switch layer.motion {
        case .fall:
            particle.position.y -= particle.velocity.dy * deltaTime
            particle.baseX += particle.velocity.dy * windDrift * deltaTime
            particle.position.x = particle.baseX + particle.swayAmplitude * sin(particle.phase)
            sprite.zRotation += particle.spinRate * deltaTime
            isFinished = particle.position.y < -layer.size || particle.position.x < -80 || particle.position.x > width + 80

        case .rise:
            particle.position.y += particle.velocity.dy * deltaTime
            particle.baseX += windDrift * 20 * deltaTime
            particle.position.x = particle.baseX + particle.swayAmplitude * sin(particle.phase)
            let climb = min(max(particle.position.y / max(particle.limit, 1), 0), 1)
            sprite.alpha = particle.baseAlpha * (1 - climb * climb)
            isFinished = particle.position.y >= particle.limit

        case .float:
            particle.velocity.dx += (CGFloat.random(in: -6...6) + windDrift * 4) * deltaTime
            particle.velocity.dy += CGFloat.random(in: -6...6) * deltaTime
            particle.velocity.dx = min(max(particle.velocity.dx, -16), 16)
            particle.velocity.dy = min(max(particle.velocity.dy, -12), 12)
            particle.position.x += particle.velocity.dx * deltaTime
            particle.position.y += particle.velocity.dy * deltaTime
            wrapInsideScene(&particle.position, margin: layer.size)
            sprite.zRotation = 0.15 * sin(particle.phase)

        case .drift:
            particle.position.x += particle.velocity.dx * deltaTime
            particle.position.y = particle.baseY + particle.swayAmplitude * sin(particle.phase)
            isFinished = particle.velocity.dx > 0 ? particle.position.x > width + layer.size : particle.position.x < -layer.size

        case .twinkle:
            let pulse = 0.5 + 0.5 * sin(particle.phase)
            sprite.alpha = particle.baseAlpha * pulse
            sprite.setScale(0.85 + 0.15 * pulse)
            isFinished = !isWanted

        case .wander:
            particle.velocity.dx += CGFloat.random(in: -40...40) * deltaTime
            particle.velocity.dy += CGFloat.random(in: -40...40) * deltaTime
            let speed = hypot(particle.velocity.dx, particle.velocity.dy)
            let maximumSpeed: CGFloat = 40
            if speed > maximumSpeed {
                particle.velocity.dx *= maximumSpeed / speed
                particle.velocity.dy *= maximumSpeed / speed
            }
            particle.position.x += particle.velocity.dx * deltaTime
            particle.position.y += particle.velocity.dy * deltaTime
            wrapInsideScene(&particle.position, margin: layer.size)
            // Face the direction of travel.
            if abs(particle.velocity.dx) > 2 {
                sprite.xScale = particle.velocity.dx < 0 ? 1 : -1
            }
            isFinished = !isWanted
        }

        if isFinished {
            if isWanted {
                spawnParticle(at: index, in: slot, layer: layer, enteringScreen: true)
            } else {
                slot.particles[index].isActive = false
                sprite.isHidden = true
            }
            return
        }

        slot.particles[index] = particle
        sprite.position = particle.position
    }

    /// Starts a particle for the layer's motion. When a layer first appears, falling and rising
    /// particles start spread across the screen instead of all entering at once.
    private func spawnParticle(at index: Int, in slot: Slot, layer: CustomLayer, enteringScreen: Bool) {
        let width = max(sceneSize.width, 1)
        let height = max(sceneSize.height, 1)
        let sprite = slot.sprites[index]
        var particle = Particle(isActive: true)
        particle.phase = CGFloat.random(in: 0...(2 * .pi))
        particle.baseAlpha = CGFloat.random(in: 0.85...1)
        sprite.zRotation = 0
        sprite.xScale = 1
        sprite.yScale = 1

        switch layer.motion {
        case .fall:
            particle.baseX = CGFloat.random(in: -40...(width + 40))
            particle.position = CGPoint(
                x: particle.baseX,
                y: enteringScreen ? height + layer.size + CGFloat.random(in: 0...(height * 0.4)) : CGFloat.random(in: 0...height)
            )
            particle.velocity.dy = CGFloat.random(in: 45...95)
            particle.swayAmplitude = CGFloat.random(in: 15...40)
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 3...6)
            particle.spinRate = CGFloat.random(in: -0.8...0.8)
            sprite.zRotation = CGFloat.random(in: -0.4...0.4)

        case .rise:
            particle.baseX = CGFloat.random(in: 0...width)
            particle.position = CGPoint(
                x: particle.baseX,
                y: enteringScreen ? -layer.size : CGFloat.random(in: 0...(height * 0.6))
            )
            particle.velocity.dy = CGFloat.random(in: 30...65)
            particle.swayAmplitude = CGFloat.random(in: 10...25)
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 2.5...4.5)
            particle.limit = height * CGFloat.random(in: 0.6...1.05)

        case .float, .wander:
            particle.position = CGPoint(x: CGFloat.random(in: 0...width), y: CGFloat.random(in: 0...height))
            particle.velocity = CGVector(dx: CGFloat.random(in: -8...8), dy: CGFloat.random(in: -8...8))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 3...6)

        case .drift:
            // Travel with the wind (or right when calm), entering from the upwind side.
            let direction: CGFloat = Bool.random(probability: 0.85) ? 1 : -1
            particle.velocity.dx = direction * CGFloat.random(in: 30...75)
            particle.baseY = CGFloat.random(in: (height * 0.12)...(height * 0.9))
            let startX = direction > 0 ? -layer.size : width + layer.size
            particle.position = CGPoint(x: enteringScreen ? startX : CGFloat.random(in: 0...width), y: particle.baseY)
            particle.swayAmplitude = CGFloat.random(in: 8...25)
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 2.5...5)
            sprite.xScale = direction > 0 ? -1 : 1   // Most emoji face left, so flip to face the way they travel.

        case .twinkle:
            particle.position = CGPoint(x: CGFloat.random(in: 0...width), y: CGFloat.random(in: (height * 0.1)...height))
            particle.phaseRate = 2 * .pi / CGFloat.random(in: 1.5...4)
        }

        slot.particles[index] = particle
        let spriteSize = layer.size * CGFloat.random(in: 0.8...1.2)
        sprite.size = CGSize(width: spriteSize, height: spriteSize)
        sprite.position = particle.position
        sprite.alpha = particle.baseAlpha
        sprite.isHidden = false
    }

    private func wrapInsideScene(_ position: inout CGPoint, margin: CGFloat) {
        if position.x < -margin { position.x = sceneSize.width + margin }
        if position.x > sceneSize.width + margin { position.x = -margin }
        if position.y < -margin { position.y = sceneSize.height + margin }
        if position.y > sceneSize.height + margin { position.y = -margin }
    }

    // MARK: - Emoji textures

    /// Renders an emoji into a texture. For recoloring, it's converted to light grayscale first,
    /// so tinting keeps the emoji's shading (a pink dragon still looks like a dragon).
    private func emojiTexture(for emoji: String, recolored: Bool) -> SKTexture {
        let cacheKey = "\(emoji)|\(recolored)"
        if let cachedTexture = Self.textureCache.object(forKey: cacheKey as NSString) {
            return cachedTexture
        }

        let canvasSize = NSSize(width: 96, height: 96)
        let emojiImage = NSImage(size: canvasSize, flipped: false) { canvas in
            let emojiText = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 76)])
            let textSize = emojiText.size()
            emojiText.draw(at: CGPoint(x: (canvas.width - textSize.width) / 2, y: (canvas.height - textSize.height) / 2))
            return true
        }

        var texture = SKTexture(image: emojiImage)
        if recolored,
           let emojiCGImage = emojiImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let grayscaleImage = lightGrayscale(emojiCGImage) {
            texture = SKTexture(cgImage: grayscaleImage)
        }
        Self.textureCache.setObject(texture, forKey: cacheKey as NSString)
        return texture
    }

    /// Removes color and brightens, so a tint color comes through clearly over the shading.
    private func lightGrayscale(_ image: CGImage) -> CGImage? {
        let colorControls = CIFilter(name: "CIColorControls")
        colorControls?.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        colorControls?.setValue(0, forKey: kCIInputSaturationKey)
        colorControls?.setValue(0.25, forKey: kCIInputBrightnessKey)
        colorControls?.setValue(1.1, forKey: kCIInputContrastKey)
        guard let outputImage = colorControls?.outputImage else { return nil }
        return Self.imageContext.createCGImage(outputImage, from: outputImage.extent)
    }
}

private extension Bool {
    /// True with the given probability.
    static func random(probability: Double) -> Bool {
        Double.random(in: 0..<1) < probability
    }
}
