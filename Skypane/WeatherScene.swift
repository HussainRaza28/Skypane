//
//  WeatherScene.swift
//  Skypane
//

import AppKit
import SpriteKit

/// Something falling particles can hit, such as snow piles on window edges and the top of the Dock.
protocol PrecipitationSurface: AnyObject {
    /// Returns true if the flake moving from `previousY` to `currentY` at `x` landed and was absorbed.
    func catchFlake(atX x: CGFloat, fromY previousY: CGFloat, toY currentY: CGFloat, depositAmount: CGFloat) -> Bool
    /// Returns true if the raindrop moving from `previousY` to `currentY` at `x` hit something and should disappear.
    func catchRaindrop(atX x: CGFloat, fromY previousY: CGFloat, toY currentY: CGFloat) -> Bool
}

/// Something that mirrors the desktop lightning flash, such as the screen-edge glow above windows.
protocol LightningObserver: AnyObject {
    /// Called every frame during a flash with its brightness, then once with 0 when it ends.
    func lightningBrightnessDidChange(_ brightness: CGFloat)
}

/// The back layer, drawn just above the desktop and behind app windows: falling snow or rain,
/// fog, lightning flashes, seasonal extras, and a night tint over the wallpaper.
/// Particles are simulated by hand so they can be checked against window and Dock edges.
final class WeatherScene: SKScene {
    /// Visual settings for one kind of particle at one depth.
    private struct ParticleStyle {
        let widthRange: ClosedRange<CGFloat>
        /// Streak length for rain; nil for round flakes.
        let lengthRange: ClosedRange<CGFloat>?
        let fallSpeedRange: ClosedRange<CGFloat>
        let alphaRange: ClosedRange<CGFloat>
        let driftAmplitudeRange: ClosedRange<CGFloat>   // How far flakes sway left and right
        let driftPeriodRange: ClosedRange<CGFloat>      // Seconds for one full sway
        let windResponse: CGFloat                       // How strongly wind pushes this particle sideways
        let depositAmount: CGFloat                      // Snow added to a pile on landing (0 = doesn't pile)
        let zPosition: CGFloat
    }

    /// Distant snowflakes: small, slow, and faint.
    private static let farSnowStyle = ParticleStyle(
        widthRange: 3.5...6, lengthRange: nil, fallSpeedRange: 30...50, alphaRange: 0.4...0.6,
        driftAmplitudeRange: 6...14, driftPeriodRange: 5...8, windResponse: 1.2, depositAmount: 0.6, zPosition: 0
    )

    /// Nearby snowflakes: larger, faster, and brighter.
    private static let nearSnowStyle = ParticleStyle(
        widthRange: 7...12, lengthRange: nil, fallSpeedRange: 65...105, alphaRange: 0.8...0.95,
        driftAmplitudeRange: 12...26, driftPeriodRange: 3.5...5.5, windResponse: 1.2, depositAmount: 1.3, zPosition: 1
    )

    /// Distant raindrops: thin, short, faint streaks.
    private static let farRainStyle = ParticleStyle(
        widthRange: 1...1.3, lengthRange: 12...18, fallSpeedRange: 520...650, alphaRange: 0.18...0.3,
        driftAmplitudeRange: 0...0, driftPeriodRange: 1...1, windResponse: 0.5, depositAmount: 0, zPosition: 0
    )

    /// Nearby raindrops: longer, faster, brighter streaks.
    private static let nearRainStyle = ParticleStyle(
        widthRange: 1.4...2, lengthRange: 22...32, fallSpeedRange: 750...950, alphaRange: 0.3...0.5,
        driftAmplitudeRange: 0...0, driftPeriodRange: 1...1, windResponse: 0.5, depositAmount: 0, zPosition: 1
    )

    /// Simulation state for one particle. Stored in a flat array so updates never allocate.
    private struct Particle {
        var isActive = false
        var isSnow = false
        var baseX: CGFloat = 0            // Horizontal position before sway is applied
        var y: CGFloat = 0
        var fallSpeed: CGFloat = 0
        var angleJitter: CGFloat = 0      // Slight random tilt, as sideways speed per unit of fall speed
        var driftAmplitude: CGFloat = 0
        var driftPhase: CGFloat = 0
        var driftRate: CGFloat = 0        // Radians per second
        var windResponse: CGFloat = 0
        var depositAmount: CGFloat = 0
    }

    // MARK: Tuning

    /// Upper limit on the particle pool, regardless of screen size.
    private let maximumParticleCount = 300
    /// Particles per point of screen width at full intensity.
    private let particlesPerPointAtFullIntensity: CGFloat = 0.2
    /// Maximum random tilt away from straight down (about 5°).
    private let angleVariance: CGFloat = 0.09
    /// Largest simulation step, so a pause or hitch doesn't teleport particles.
    private let maximumTimeStep: TimeInterval = 1.0 / 20.0
    /// How quickly wind, fog, and tint ease toward new values (fraction per second).
    private let environmentEasingRate: CGFloat = 0.4

    /// Fog opacity at full fog amount.
    private let maximumFogAlpha: CGFloat = 0.32
    private let maximumSkyTintAlpha: CGFloat = 0.3
    /// Seconds between lightning strikes during a thunderstorm.
    private let lightningIntervalRange: ClosedRange<CGFloat> = 5...18

    // MARK: State

    /// What falling particles can hit. Set by the overlay that owns this scene.
    weak var precipitationSurface: PrecipitationSurface?
    /// Mirrors lightning flashes above app windows. Set by the overlay that owns this scene.
    weak var lightningObserver: LightningObserver?
    /// This screen's bottom-left corner in global coordinates, for converting the cursor position.
    var screenOrigin: CGPoint = .zero
    /// Whether moving the cursor wipes fog. Set from the Settings window.
    var cursorInteracts = true {
        didSet { cursorMotion = CursorMotion() }
    }

    /// Frame rates while something is moving, and while only the still tint is showing.
    private let activeFramesPerSecond = 60
    private let idleFramesPerSecond = 10
    /// After this long with nothing changing, the layer stops drawing until something new arrives.
    private let sleepAfterIdleDuration: CGFloat = 2
    private var idleDuration: CGFloat = 0

    /// Whether this screen's overlay is showing. The layer only wakes itself while it is.
    var allowsDrawing = true

    private var effect = WeatherEffect.fallbackSnow
    private var targetSkyTint = SkyTint.none

    private var particles: [Particle] = []
    private var particleSprites: [SKSpriteNode] = []
    private var targetParticleCount = 0
    /// Eased sideways wind push, so changes in wind ramp smoothly.
    private var currentWindDrift: CGFloat = 0

    private let fogLayer = FogLayer()
    private let ambientLayer = AmbientEffectsLayer()
    private let customLayer = CustomParticleLayer()
    private var cursorMotion = CursorMotion()

    private let lightningFlashNode = SKSpriteNode(color: .white, size: .zero)
    private var timeUntilNextLightning: CGFloat = 8
    private var lightningFlashElapsed: CGFloat?

    private let nightTintNode = SKSpriteNode()

    private var lastUpdateTime: TimeInterval?

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
        guard particleSprites.isEmpty else { return }

        setUpFullScreenNodes()

        // Fog sits above the particles, so it softens them.
        fogLayer.containerNode.zPosition = 3
        addChild(fogLayer.containerNode)
        fogLayer.layOut(sceneSize: size)

        // Decorative effects (leaves, fireflies, auroras, and so on) sit between the particles and the fog.
        ambientLayer.containerNode.zPosition = 2
        addChild(ambientLayer.containerNode)
        ambientLayer.layOut(sceneSize: size)
        ambientLayer.apply(effect.ambientLayers)

        // Emoji layers for anything that isn't a built-in effect, just above the built-in ones.
        customLayer.containerNode.zPosition = 2.5
        addChild(customLayer.containerNode)
        customLayer.layOut(sceneSize: size)
        customLayer.apply(effect.customLayers)

        // Build the full particle pool once; particles are recycled instead of created and destroyed.
        particles = Array(repeating: Particle(), count: maximumParticleCount)
        particleSprites.reserveCapacity(maximumParticleCount)
        for _ in 0..<maximumParticleCount {
            let particleSprite = SKSpriteNode(texture: WeatherTextures.softFlake)
            particleSprite.isHidden = true
            addChild(particleSprite)
            particleSprites.append(particleSprite)
        }

        // Start with particles already spread over the screen so it's already snowing or raining.
        currentWindDrift = effect.windDrift
        updateTargetParticleCount()
        for index in 0..<targetParticleCount {
            spawnParticle(at: index, anywhereOnScreen: true)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard !particleSprites.isEmpty else { return }
        layOutFullScreenNodes()
        fogLayer.layOut(sceneSize: size)
        ambientLayer.layOut(sceneSize: size)
        customLayer.layOut(sceneSize: size)
        updateTargetParticleCount()
    }

    // MARK: - Weather input

    /// Switches to new weather. Falling particles finish their fall; new ones use the new weather.
    func apply(_ newEffect: WeatherEffect) {
        effect = newEffect
        wake()
        fogLayer.setColor(newEffect.fogColor)
        guard !particleSprites.isEmpty else { return }
        ambientLayer.apply(newEffect.ambientLayers)
        customLayer.apply(newEffect.customLayers)
        updateTargetParticleCount()
    }

    /// Sets the color wash over the desktop (night darkening, or a typed scene's mood color). It fades in gradually.
    func apply(_ skyTint: SkyTint) {
        targetSkyTint = skyTint
        wake()
    }

    /// Resumes drawing after the layer went to sleep.
    func wake() {
        idleDuration = 0
        guard allowsDrawing, let view, view.isPaused else { return }
        lastUpdateTime = nil
        view.isPaused = false
    }

    private func updateTargetParticleCount() {
        // Snow and rain share the pool, so together they never exceed the maximum.
        let totalIntensity = min(effect.snowIntensity + effect.rainIntensity, 1)
        let desiredCount = size.width * particlesPerPointAtFullIntensity * totalIntensity
        targetParticleCount = min(maximumParticleCount, Int(desiredCount))
    }

    // MARK: - Per-frame update

    override func update(_ currentTime: TimeInterval) {
        let deltaTime = CGFloat(min(currentTime - (lastUpdateTime ?? currentTime), maximumTimeStep))
        lastUpdateTime = currentTime
        guard deltaTime > 0 else { return }

        let easing = min(1, environmentEasingRate * deltaTime)
        currentWindDrift += (effect.windDrift - currentWindDrift) * easing

        updateParticles(deltaTime: deltaTime)
        ambientLayer.update(deltaTime: deltaTime, windDrift: currentWindDrift)
        customLayer.update(deltaTime: deltaTime, windDrift: currentWindDrift)

        fogLayer.update(
            deltaTime: deltaTime,
            easing: easing,
            targetAlpha: effect.fogAmount * maximumFogAlpha,
            windDrift: currentWindDrift
        )
        // The cursor wipes fog wherever it passes.
        if cursorInteracts, let cursorMovement = cursorMotion.update(screenOrigin: screenOrigin, deltaTime: deltaTime) {
            fogLayer.wipe(along: cursorMovement)
        }

        updateLightning(deltaTime: deltaTime)
        updateSkyTint(easing: easing)
        updateFrameRate(deltaTime: deltaTime)
    }

    /// Draws at full speed while anything moves, slowly when the layer is empty, and not at all
    /// once nothing has changed for a couple of seconds, to save power.
    private func updateFrameRate(deltaTime: CGFloat) {
        let isIdle = targetParticleCount == 0
            && !particles.contains(where: \.isActive)
            && !fogLayer.isVisible
            && !ambientLayer.isShowingAnything
            && !customLayer.isShowingAnything
            && lightningFlashElapsed == nil
            && !effect.hasLightning
        let framesPerSecond = isIdle ? idleFramesPerSecond : activeFramesPerSecond
        if let view, view.preferredFramesPerSecond != framesPerSecond {
            view.preferredFramesPerSecond = framesPerSecond
        }

        let isTintSettled = abs(targetSkyTint.strength * maximumSkyTintAlpha - nightTintNode.alpha) < 0.002
        idleDuration = isIdle && isTintSettled ? idleDuration + deltaTime : 0
        if idleDuration > sleepAfterIdleDuration {
            view?.isPaused = true
        }
    }

    private func updateParticles(deltaTime: CGFloat) {
        for index in 0..<particles.count {
            guard particles[index].isActive else {
                // Bring in more particles when the weather gets heavier, entering from above the screen.
                if index < targetParticleCount {
                    spawnParticle(at: index, anywhereOnScreen: false)
                }
                continue
            }

            var particle = particles[index]
            let previousY = particle.y

            // Fall, tilt with the wind, and (for snow) sway with a sine wave for a naturally eased drift.
            let sidewaysSpeed = particle.fallSpeed * (particle.angleJitter + currentWindDrift * particle.windResponse)
            particle.y -= particle.fallSpeed * deltaTime
            particle.baseX += sidewaysSpeed * deltaTime
            var particleX = particle.baseX
            if particle.driftAmplitude > 0 {
                particle.driftPhase += particle.driftRate * deltaTime
                particleX += particle.driftAmplitude * sin(particle.driftPhase)
            }

            // Snowflakes can land on piles and raindrops can splash on the Dock; anything leaving the screen is recycled.
            let didHitSurface: Bool
            if particle.isSnow {
                didHitSurface = precipitationSurface?.catchFlake(
                    atX: particleX, fromY: previousY, toY: particle.y, depositAmount: particle.depositAmount
                ) ?? false
            } else {
                didHitSurface = precipitationSurface?.catchRaindrop(
                    atX: particleX, fromY: previousY, toY: particle.y
                ) ?? false
            }
            let leftScreen = particle.y < -40
                || (sidewaysSpeed > 0 && particleX > size.width + 60)
                || (sidewaysSpeed < 0 && particleX < -60)
            if didHitSurface || leftScreen {
                recycleParticle(at: index)
                continue
            }

            particles[index] = particle
            let particleSprite = particleSprites[index]
            particleSprite.position = CGPoint(x: particleX, y: particle.y)
            if !particle.isSnow {
                // Lean rain streaks along their direction of travel.
                particleSprite.zRotation = atan(sidewaysSpeed / particle.fallSpeed)
            }
        }
    }

    /// Respawns a finished particle at the top, or retires it if the weather now needs fewer.
    private func recycleParticle(at index: Int) {
        if index < targetParticleCount {
            spawnParticle(at: index, anywhereOnScreen: false)
        } else {
            particles[index].isActive = false
            particleSprites[index].isHidden = true
        }
    }

    /// Gives a particle fresh random properties for the current weather and places it above the
    /// screen (or anywhere on it, when first filling the screen).
    private func spawnParticle(at index: Int, anywhereOnScreen: Bool) {
        // When snow and rain fall together, each particle picks one in proportion to their intensities.
        let totalIntensity = effect.snowIntensity + effect.rainIntensity
        let isSnow = totalIntensity > 0 && CGFloat.random(in: 0..<totalIntensity) < effect.snowIntensity
        let isFar = index % 5 < 3   // Three of every five particles are distant, the rest are near.
        let style: ParticleStyle = switch (isSnow, isFar) {
        case (true, true): Self.farSnowStyle
        case (true, false): Self.nearSnowStyle
        case (false, true): Self.farRainStyle
        case (false, false): Self.nearRainStyle
        }

        let fallSpeed = CGFloat.random(in: style.fallSpeedRange)
        let width = CGFloat.random(in: style.widthRange)
        let length = style.lengthRange.map { CGFloat.random(in: $0) } ?? width

        // Start upwind so wind-blown particles still cover the whole screen.
        let sidewaysTravel = currentWindDrift * style.windResponse * size.height
        let spawnMinX = min(0, -sidewaysTravel) - 20
        let spawnMaxX = max(size.width, size.width - sidewaysTravel) + 20

        let startY = anywhereOnScreen
            ? CGFloat.random(in: 0...max(size.height, 1))
            : size.height + length + CGFloat.random(in: 0...(size.height * 0.5))

        particles[index] = Particle(
            isActive: true,
            isSnow: isSnow,
            baseX: CGFloat.random(in: spawnMinX...spawnMaxX),
            y: startY,
            fallSpeed: fallSpeed,
            angleJitter: CGFloat.random(in: -angleVariance...angleVariance),
            driftAmplitude: CGFloat.random(in: style.driftAmplitudeRange),
            driftPhase: CGFloat.random(in: 0...(2 * .pi)),
            driftRate: 2 * .pi / CGFloat.random(in: style.driftPeriodRange),
            windResponse: style.windResponse,
            depositAmount: style.depositAmount
        )

        let particleSprite = particleSprites[index]
        if isSnow {
            // Near flakes are sometimes clumps; far flakes are always single soft flakes.
            let useClump = !isFar && Bool.random()
            particleSprite.texture = useClump
                ? WeatherTextures.flakeClumps[index % WeatherTextures.flakeClumps.count]
                : WeatherTextures.softFlake
            particleSprite.zRotation = CGFloat.random(in: 0...(2 * .pi))
        } else {
            particleSprite.texture = WeatherTextures.rainStreak
            particleSprite.zRotation = 0
        }
        // Snow and rain can be recolored in typed scenes (orange snow, purple rain).
        let particleColor = isSnow ? effect.snowColor : effect.rainColor
        particleSprite.color = particleColor ?? .white
        particleSprite.colorBlendFactor = particleColor == nil ? 0 : 1
        particleSprite.size = CGSize(width: width, height: length)
        particleSprite.alpha = CGFloat.random(in: style.alphaRange)
        particleSprite.zPosition = style.zPosition
        particleSprite.position = CGPoint(x: particles[index].baseX, y: startY)
        particleSprite.isHidden = false
    }

    // MARK: - Lightning

    /// Counts down to the next strike during thunderstorms and plays a quick double flash.
    private func updateLightning(deltaTime: CGFloat) {
        if let elapsed = lightningFlashElapsed {
            let flashTime = elapsed + deltaTime
            if let flashAlpha = lightningAlpha(at: flashTime) {
                lightningFlashNode.alpha = flashAlpha
                lightningFlashElapsed = flashTime
                lightningObserver?.lightningBrightnessDidChange(flashAlpha)
            } else {
                lightningFlashNode.isHidden = true
                lightningFlashElapsed = nil
                lightningObserver?.lightningBrightnessDidChange(0)
            }
            return
        }

        guard effect.hasLightning else { return }
        timeUntilNextLightning -= deltaTime
        if timeUntilNextLightning <= 0 {
            timeUntilNextLightning = CGFloat.random(in: lightningIntervalRange)
            lightningFlashElapsed = 0
            lightningFlashNode.isHidden = false
        }
    }

    /// Brightness of a lightning flash over time: a bright strike, a flicker, then a fade. Nil when done.
    private func lightningAlpha(at flashTime: CGFloat) -> CGFloat? {
        switch flashTime {
        case ..<0.07: 0.32
        case ..<0.15: 0.06
        case ..<0.24: 0.22
        case ..<0.7: 0.22 * (1 - (flashTime - 0.24) / 0.46)
        default: nil
        }
    }

    // MARK: - Sky tint

    private func updateSkyTint(easing: CGFloat) {
        let targetNightAlpha = targetSkyTint.strength * maximumSkyTintAlpha
        nightTintNode.color = targetSkyTint.color

        nightTintNode.alpha += (targetNightAlpha - nightTintNode.alpha) * easing

        // Skip drawing full-screen layers that are effectively invisible.
        nightTintNode.isHidden = nightTintNode.alpha < 0.005
    }

    // MARK: - Full-screen layers

    private func setUpFullScreenNodes() {
        // The night tint sits under everything so it only darkens the wallpaper.
        nightTintNode.color = SkyTint.nightColor
        nightTintNode.zPosition = -10
        // Lightning lights up everything on the desktop, so it sits on top.
        lightningFlashNode.zPosition = 5

        for fullScreenNode in [nightTintNode, lightningFlashNode] {
            fullScreenNode.anchorPoint = .zero
            fullScreenNode.position = .zero
            fullScreenNode.alpha = 0
            fullScreenNode.isHidden = true
            addChild(fullScreenNode)
        }
        layOutFullScreenNodes()
    }

    private func layOutFullScreenNodes() {
        for fullScreenNode in [nightTintNode, lightningFlashNode] {
            fullScreenNode.size = size
        }
    }
}
