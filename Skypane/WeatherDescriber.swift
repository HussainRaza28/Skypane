//
//  WeatherDescriber.swift
//  Skypane
//

import AppKit
import FoundationModels
import os

/// A typed scene, ready to show on screen.
struct DescribedWeather: Equatable {
    /// What the person typed (including any follow-up changes).
    let text: String
    /// A short name for the scene, written by the model.
    let title: String
    /// A one-line list of what's in the scene, such as "light snow · 🐉 pink, falling".
    let summary: String
    let effect: WeatherEffect
    let skyTint: SkyTint
    /// The settings behind the scene, so follow-up requests can adjust it.
    let settings: SceneSettings
}

/// A typed scene's settings, which follow-up requests adjust one part at a time.
struct SceneSettings: Equatable {
    var title: String
    var snow: Level
    var snowColor: GeneratedColor
    var rain: Level
    var rainColor: GeneratedColor
    var wind: WindLevel
    var fog: Level
    var fogColor: GeneratedColor
    var lightning: Bool
    var layers: [GeneratedLayer]
    var skyColor: GeneratedColor
    var skyStrength: TintLevel

    init(_ scene: GeneratedScene) {
        title = scene.title
        snow = scene.snow
        snowColor = scene.snowColor
        rain = scene.rain
        rainColor = scene.rainColor
        wind = scene.wind
        fog = scene.fog
        fogColor = scene.fogColor
        lightning = scene.lightning
        layers = scene.layers
        skyColor = scene.skyColor
        skyStrength = scene.skyStrength
    }
}

// MARK: - Generated scene

/// A scene the on-device model designs from a description. Anything can appear: weather has its
/// own fields, and everything else is a layer that uses a built-in effect when one matches or an
/// emoji when none does. Amounts are levels and colors are names, which the on-device model picks
/// far more reliably than numbers.
@Generable(description: "An animated scene for a Mac desktop")
struct GeneratedScene: Equatable {
    @Guide(description: "A short, evocative title for the scene, two to five words")
    var title: String

    @Guide(description: "Snowfall; none unless snow, winter, or a blizzard is requested")
    var snow: Level
    @Guide(description: "Snow color; natural unless the request gives the snow a color")
    var snowColor: GeneratedColor

    @Guide(description: "Rainfall; none unless rain, drizzle, or a storm is requested")
    var rain: Level
    @Guide(description: "Rain color; natural unless the request gives the rain a color")
    var rainColor: GeneratedColor

    @Guide(description: "Wind; calm unless wind, a breeze, a blizzard, or a storm is requested")
    var wind: WindLevel

    @Guide(description: "Fog; none unless fog, mist, or haze is requested")
    var fog: Level
    @Guide(description: "Fog color; natural unless the request gives the fog a color")
    var fogColor: GeneratedColor

    @Guide(description: "True only for thunderstorms and lightning")
    var lightning: Bool

    @Guide(description: "Every other thing the request asks to see, one layer each; empty if nothing else is asked for", .maximumCount(4))
    var layers: [GeneratedLayer]

    @Guide(description: "Background tint; natural unless the request mentions the sky, background, time of day, or a mood")
    var skyColor: GeneratedColor
    @Guide(description: "Strength of the background tint; none unless the request mentions the sky, background, time of day, or a mood")
    var skyStrength: TintLevel
}

/// One thing to show: a built-in effect, or an emoji for anything else.
@Generable(description: "One thing to show on screen")
struct GeneratedLayer: Equatable {
    @Guide(description: "What this layer shows, in one to three words, such as pink dragons")
    var subject: String

    @Guide(description: "The built-in effect that matches the subject, or none to draw the subject as an emoji")
    var builtIn: BuiltInEffect

    @Guide(description: "One emoji that looks like the subject, such as 🐉 for dragons or 🍕 for pizza")
    var emoji: String

    @Guide(description: "The color the request gives this subject, or natural")
    var color: GeneratedColor

    @Guide(description: "How it moves: fall, rise, float, drift sideways, twinkle in place, or wander")
    var motion: GeneratedMotion

    @Guide(description: "How many: light, medium, or heavy")
    var amount: Level

    @Guide(description: "How big each one is")
    var size: SizeLevel
}

/// Effects Skypane draws by hand. To add one: add a case, its keywords, and its renderer. Any
/// layer whose subject matches the keywords then uses it instead of an emoji.
@Generable
enum BuiltInEffect: Equatable, CaseIterable {
    case none, leaves, petals, confetti, fireflies, embers, bubbles, stars, dust, aurora, shootingStars

    /// Words in a layer's subject that mean this effect. Checked in `allCases` order after
    /// `matchingOrder`, so "shooting star" wins over "star".
    var keywords: [String] {
        switch self {
        case .none: []
        case .leaves: ["leaf", "leaves", "autumn", "foliage"]
        case .petals: ["petal", "blossom", "sakura", "cherry"]
        case .confetti: ["confetti"]
        case .fireflies: ["firefl"]
        case .embers: ["ember", "campfire", "bonfire", "fireplace", "spark"]
        case .bubbles: ["bubble"]
        case .stars: ["star"]
        case .dust: ["dust", "sunbeam", "mote", "glitter"]
        case .aurora: ["aurora", "northern light"]
        case .shootingStars: ["shooting star", "falling star", "meteor", "comet"]
        }
    }

    /// The order to check keywords in, most specific first.
    static let matchingOrder: [BuiltInEffect] = [
        .shootingStars, .aurora, .fireflies, .leaves, .petals, .confetti, .embers, .bubbles, .dust, .stars,
    ]

    /// The built-in effect a subject describes, or `.none` if it should be drawn as an emoji.
    static func matching(_ subject: String) -> BuiltInEffect {
        let subjectWords = subject.lowercased()
        return matchingOrder.first { effect in effect.keywords.contains { subjectWords.contains($0) } } ?? .none
    }

    var ambientKind: AmbientKind? {
        switch self {
        case .none: nil
        case .leaves: .leaves
        case .petals: .petals
        case .confetti: .confetti
        case .fireflies: .fireflies
        case .embers: .embers
        case .bubbles: .bubbles
        case .stars: .stars
        case .dust: .dust
        case .aurora: .aurora
        case .shootingStars: .shootingStars
        }
    }
}

@Generable
enum GeneratedMotion: Equatable {
    case fall, rise, float, drift, twinkle, wander

    var customMotion: CustomMotion {
        switch self {
        case .fall: .fall
        case .rise: .rise
        case .float: .float
        case .drift: .drift
        case .twinkle: .twinkle
        case .wander: .wander
        }
    }
}

@Generable
enum SizeLevel: Equatable {
    case small, medium, large

    var points: CGFloat {
        switch self {
        case .small: 18
        case .medium: 30
        case .large: 46
        }
    }
}

/// How much of something there is.
@Generable
enum Level: Equatable, CaseIterable {
    case none, light, medium, heavy

    var amount: Double {
        switch self {
        case .none: 0
        case .light: 0.3
        case .medium: 0.6
        case .heavy: 1
        }
    }

    /// One step up or down, staying within none...heavy.
    func stepped(by offset: Int) -> Level {
        let allLevels = Level.allCases
        let index = allLevels.firstIndex(of: self) ?? 0
        return allLevels[min(max(index + offset, 0), allLevels.count - 1)]
    }
}

/// How hard and which way the wind blows.
@Generable
enum WindLevel: Equatable {
    case calm, breezeLeft, breezeRight, strongLeft, strongRight

    var drift: Double {
        switch self {
        case .calm: 0
        case .breezeLeft: -0.4
        case .breezeRight: 0.4
        case .strongLeft: -0.9
        case .strongRight: 0.9
        }
    }
}

/// How strong the background tint is.
@Generable
enum TintLevel: Equatable {
    case none, subtle, strong

    var strength: Double {
        switch self {
        case .none: 0
        case .subtle: 0.5
        case .strong: 1
        }
    }
}

/// A color by name, which the on-device model picks far more reliably than numbers.
@Generable
enum GeneratedColor: Equatable {
    case natural
    case white, cream, silver, gold, amber, orange, coral, red, crimson, rose, pink, magenta
    case lavender, purple, violet, indigo, navy, blue, skyBlue, teal, cyan, mint, green, emerald

    /// The color to draw, or nil for "natural" (the effect's own colors).
    var nsColor: NSColor? {
        let rgb: (CGFloat, CGFloat, CGFloat)? = switch self {
        case .natural: nil
        case .white: (255, 255, 255)
        case .cream: (255, 244, 214)
        case .silver: (205, 214, 226)
        case .gold: (255, 205, 80)
        case .amber: (255, 166, 70)
        case .orange: (255, 128, 40)
        case .coral: (255, 120, 100)
        case .red: (235, 50, 45)
        case .crimson: (190, 20, 60)
        case .rose: (240, 130, 160)
        case .pink: (255, 140, 200)
        case .magenta: (230, 60, 200)
        case .lavender: (190, 160, 255)
        case .purple: (150, 80, 220)
        case .violet: (120, 70, 255)
        case .indigo: (60, 50, 160)
        case .navy: (10, 18, 51)
        case .blue: (40, 100, 240)
        case .skyBlue: (120, 190, 255)
        case .teal: (30, 170, 170)
        case .cyan: (60, 220, 240)
        case .mint: (140, 240, 190)
        case .green: (60, 200, 90)
        case .emerald: (20, 160, 110)
        }
        return rgb.map { NSColor(calibratedRed: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255, alpha: 1) }
    }

    /// Colors too dark to show up as light (for stars, embers, auroras, and other glowing effects).
    var isTooDarkToGlow: Bool {
        switch self {
        case .navy, .indigo, .crimson: true
        default: false
        }
    }
}

extension GeneratedColor {
    /// Every real color (everything except "natural").
    static let allNamed: [GeneratedColor] = [
        .white, .cream, .silver, .gold, .amber, .orange, .coral, .red, .crimson, .rose, .pink, .magenta,
        .lavender, .purple, .violet, .indigo, .navy, .blue, .skyBlue, .teal, .cyan, .mint, .green, .emerald,
    ]

    /// How people write this color, for checking that a request actually named it.
    var spokenNames: [String] {
        switch self {
        case .natural: []
        case .skyBlue: ["sky blue", "light blue", "baby blue"]
        default: ["\(self)".lowercased()]
        }
    }
}

/// The model's answer when double-checking one element of a new scene.
@Generable
struct ElementCheck {
    @Guide(description: "One short sentence on whether someone picturing the description would see this element")
    var reasoning: String

    @Guide(description: "True only if the description asks for the element or it is an obvious part of that scene")
    var isRequested: Bool
}

// MARK: - Generated changes

/// A change to the current scene, such as "more wind" or "make the dragons blue". The model only
/// describes what changes; the code applies it, so everything else stays exactly as it was.
@Generable(description: "A change to a desktop scene. Use keep, natural, and empty lists for anything not mentioned.")
struct GeneratedSceneChange {
    @Guide(description: "A short new title for the changed scene, two to five words")
    var title: String

    @Guide(description: "What to do with snowfall; keep unless the request mentions snow")
    var snow: LevelChange
    @Guide(description: "A new snow color, or natural to keep the current one")
    var snowColor: GeneratedColor

    @Guide(description: "What to do with rainfall; keep unless the request mentions rain")
    var rain: LevelChange
    @Guide(description: "A new rain color, or natural to keep the current one")
    var rainColor: GeneratedColor

    @Guide(description: "What to do with wind; keep unless the request mentions wind")
    var wind: WindChange

    @Guide(description: "What to do with fog; keep unless the request mentions fog or mist")
    var fog: LevelChange

    @Guide(description: "What to do with lightning; keep unless the request mentions lightning or storms")
    var lightning: LightningChange

    @Guide(description: "New things to show, or existing things with a new color, motion, or amount; only what the request mentions", .maximumCount(3))
    var layersToAdd: [GeneratedLayer]

    @Guide(description: "Subjects to take away, only if the request asks to remove them", .maximumCount(4))
    var layersToRemove: [String]

    @Guide(description: "A new background tint, or natural to keep the current one")
    var newSkyColor: GeneratedColor
    @Guide(description: "What to do with the background tint strength; keep unless the request mentions it")
    var skyStrength: TintChange
}

@Generable
enum LevelChange: Equatable {
    case keep, increase, decrease, remove
}

@Generable
enum WindChange: Equatable {
    case keep, calm, stronger, weaker, blowLeft, blowRight
}

@Generable
enum LightningChange: Equatable {
    case keep, turnOn, turnOff
}

@Generable
enum TintChange: Equatable {
    case keep, none, subtle, strong
}

// MARK: - Describer

/// Designs scenes from descriptions with Apple's on-device model when Apple Intelligence is
/// available (no network; nothing leaves the Mac). The model fills in a structured scene, then
/// double-checks anything the request didn't name. Follow-up requests change the current scene
/// step by step. Without the model, it falls back to recognizing common words.
final class WeatherDescriber {
    enum Mode {
        /// A new scene from the description.
        case newScene
        /// A change to the scene that's showing.
        case changeCurrentScene
        /// A scene the model invents on its own.
        case surprise
    }

    private static let builtInNames = BuiltInEffect.allCases.filter { $0 != .none }.map { "\($0)" }.joined(separator: ", ")

    private let sceneInstructions = """
        You design animated scenes for a Mac desktop. Anything can appear: weather, animals, food, \
        objects, symbols. Include everything the request asks for and nothing else.
        Snow, rain, wind, fog, and lightning have their own fields. Everything else is a layer. Use a \
        built-in effect when one matches (\(builtInNames)); otherwise set builtIn to none and pick one emoji.
        Give a color only to the thing the request colors. "Raining" or "falling" things fall; they \
        are not water rain unless rain itself is asked for. Otherwise pick motions that suit each \
        thing: leaves and dragons fall, balloons rise, birds and fish drift, stars twinkle, \
        butterflies wander. Wind stays calm unless the request mentions wind.
        Example: "purple owls and rain" is medium rain and one layer: subject purple owls, builtIn \
        none, emoji 🦉, color purple, motion drift.
        """
    private let surpriseInstructions = """
        You invent delightful, surprising animated scenes for a Mac desktop. Combine some weather with \
        two or three playful layers, and make at least one of them an unexpected emoji subject, like \
        animals, food, or objects. Use bold colors and motions that suit each thing, and a background \
        tint that sets the mood.
        """
    private let changeInstructions = """
        You adjust an animated desktop scene. Describe only the requested change and use keep, \
        natural, and empty lists for everything else. "Remove the snow" sets snow to remove. "More \
        wind" sets wind to stronger. "Add kites" adds one kite layer. "Make the kites green" adds the \
        kite layer again with color green. Add only things the request names.
        """
    /// Lower randomness keeps the model close to what was asked; surprises get more.
    private let generationOptions = GenerationOptions(temperature: 0.3)
    private let surpriseOptions = GenerationOptions(temperature: 1.0)
    /// Most layers a scene can hold (emoji layers are further limited by the renderer).
    private let maximumLayerCount = 6
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skypane", category: "Describe")

    /// Whether the on-device model can be used right now.
    var isOnDeviceModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Designs a scene. For `.changeCurrentScene`, `currentScene` is adjusted instead of replaced.
    func weather(for request: String, mode: Mode, currentScene: DescribedWeather?) async -> DescribedWeather {
        let changingScene = mode == .changeCurrentScene ? currentScene : nil
        let fullText = changingScene.map { "\($0.text), \(request)" } ?? request

        if isOnDeviceModelAvailable {
            do {
                switch mode {
                case .changeCurrentScene where changingScene != nil:
                    let session = LanguageModelSession(instructions: changeInstructions)
                    let response = try await session.respond(
                        to: Self.changePrompt(request: request, currentScene: changingScene!.settings),
                        generating: GeneratedSceneChange.self,
                        options: generationOptions
                    )
                    let changedSettings = applying(response.content, to: changingScene!.settings, request: request)
                    return makeWeather(from: normalized(changedSettings), text: fullText)

                case .surprise:
                    let session = LanguageModelSession(instructions: surpriseInstructions)
                    let response = try await session.respond(
                        to: "Invent a scene that would make someone smile.",
                        generating: GeneratedScene.self,
                        options: surpriseOptions
                    )
                    let surpriseSettings = normalized(SceneSettings(response.content))
                    return makeWeather(from: surpriseSettings, text: surpriseSettings.title)

                default:
                    let session = LanguageModelSession(instructions: sceneInstructions)
                    let response = try await session.respond(to: request, generating: GeneratedScene.self, options: generationOptions)
                    let guardedSettings = keepingOnlyNamedColorsAndSky(normalized(SceneSettings(response.content)), request: request)
                    let verifiedSettings = await removingUnrequestedElements(from: guardedSettings, request: request)
                    return makeWeather(from: verifiedSettings, text: fullText)
                }
            } catch {
                logger.error("On-device model couldn't design a scene: \(error.localizedDescription, privacy: .public)")
            }
        }
        let keywordText = mode == .surprise ? "snow, stars, and fireflies at night" : fullText
        return makeWeather(from: normalized(SceneSettings(Self.keywordScene(for: keywordText))), text: keywordText)
    }

    /// Describes the current scene to the model along with the requested change.
    private static func changePrompt(request: String, currentScene: SceneSettings) -> String {
        let layerList = currentScene.layers.map { layer in
            "\(layer.subject) (\(layer.builtIn == .none ? layer.emoji : "\(layer.builtIn)"), \(layer.color), \(layer.motion), \(layer.amount))"
        }.joined(separator: "; ")
        return """
            Current scene: snow \(currentScene.snow) \(currentScene.snowColor), rain \(currentScene.rain) \
            \(currentScene.rainColor), wind \(currentScene.wind), fog \(currentScene.fog), lightning \
            \(currentScene.lightning), layers: \(layerList.isEmpty ? "none" : layerList), background \
            \(currentScene.skyColor) at \(currentScene.skyStrength).
            Requested change: \(request)
            """
    }

    // MARK: - Normalizing

    /// Emoji the model sometimes uses for weather that has its own renderer.
    private static let snowEmoji: Set<String> = ["❄️", "❄", "🌨️", "🌨", "☃️", "⛄"]
    private static let rainEmoji: Set<String> = ["🌧️", "🌧", "💧", "☔", "☔️", "🌦️"]

    /// Makes the model's layers consistent: built-in effects are chosen by their keywords (so a
    /// dragon is never drawn as leaves), snow and rain emoji become real snow and rain, and
    /// duplicate layers are dropped.
    private func normalized(_ settings: SceneSettings) -> SceneSettings {
        var scene = settings
        var layers: [GeneratedLayer] = []

        for var layer in settings.layers where layer.amount != .none {
            // Weather and the sky have their own fields, even if the model made them a layer.
            let subjectWords = Set(layer.subject.lowercased().split { !$0.isLetter }.map(String.init))
            if !subjectWords.isDisjoint(with: ["snow", "snowflake", "snowflakes", "snowfall", "flurries"]) {
                scene.snow = heavierLevel(scene.snow, layer.amount)
                if layer.color != .natural { scene.snowColor = layer.color }
                continue
            }
            if !subjectWords.isDisjoint(with: ["rain", "raindrop", "raindrops", "rainfall", "drizzle"]) {
                scene.rain = heavierLevel(scene.rain, layer.amount)
                if layer.color != .natural { scene.rainColor = layer.color }
                continue
            }
            if !subjectWords.isDisjoint(with: ["fog", "mist", "haze"]) {
                scene.fog = heavierLevel(scene.fog, layer.amount)
                if layer.color != .natural { scene.fogColor = layer.color }
                continue
            }
            if !subjectWords.isDisjoint(with: ["sky", "background"]) {
                continue
            }

            layer.builtIn = BuiltInEffect.matching(layer.subject)
            if layer.builtIn == .none {
                let emoji = Self.validatedEmoji(layer.emoji) ?? "✨"
                if Self.snowEmoji.contains(emoji) {
                    scene.snow = heavierLevel(scene.snow, layer.amount)
                    if layer.color != .natural { scene.snowColor = layer.color }
                    continue
                }
                if Self.rainEmoji.contains(emoji) {
                    scene.rain = heavierLevel(scene.rain, layer.amount)
                    if layer.color != .natural { scene.rainColor = layer.color }
                    continue
                }
                layer.emoji = emoji
            }

            let isDuplicate = layers.contains { existing in
                layer.builtIn != .none ? existing.builtIn == layer.builtIn : (existing.builtIn == .none && existing.emoji == layer.emoji)
            }
            if !isDuplicate {
                layers.append(layer)
            }
        }
        scene.layers = Array(layers.prefix(maximumLayerCount))
        return scene
    }

    // MARK: - Guards

    /// Words that let a request touch each part of the scene. Reductions, removals, and recoloring
    /// only apply to parts the request mentions, so the model can't change things nobody talked about.
    private static let mentionWords: [String: [String]] = [
        "snow": ["snow", "flake", "winter", "blizzard", "flurr"],
        "rain": ["rain", "drizzle", "storm", "shower", "wet", "pour"],
        "fog": ["fog", "mist", "haze"],
        "wind": ["wind", "breez", "gust", "calm", "still", "blow", "storm"],
        "lightning": ["lightning", "thunder", "storm"],
        "sky": ["sky", "background", "night", "evening", "midnight", "dusk", "sunset", "sunrise", "dawn",
                "dark", "dreamy", "cozy", "moody", "spooky", "gloomy", "golden", "tint", "mood", "glow"],
    ]
    private static let wholeSceneWords = ["only", "just", "nothing but", "everything", "all of"]
    /// Phrases that ask to take something away. They always remove what they name (and only that),
    /// even if the model's answer missed it.
    private static let removalPhrases = ["remove", "no more", "stop the", "get rid of", "without", "take away", "delete", "turn off", " no "]
    /// Words that ask for less of something.
    private static let reductionWords = ["less", "fewer", "lighter", "softer", "weaker", "reduce", "lower", "calmer", "gentler", "smaller"]
    /// The short word keys that identify each weather part in a removal.
    private static let weatherKeys: [String: [String]] = [
        "snow": ["snow", "flak", "flur", "bliz"],
        "rain": ["rain", "driz"],
        "fog": ["fog", "mist", "haze"],
        "lightning": ["ligh", "thun"],
        "wind": ["wind", "bree", "gust"],
    ]

    /// Phrases that ask for more of something, or to add it.
    private static let increasePhrases = ["more", "add", "heavier", "stronger", "extra", "lots of", "bigger"]

    /// The keys (first four letters) of the words right after each removal phrase, up to the next
    /// "and" or comma: "remove the confetti and add pizza" gives ["conf"].
    private static func removedKeys(in request: String) -> Set<String> {
        keys(after: removalPhrases, in: request)
    }

    /// The keys of the words right after any of these phrases, up to the next "and" or comma.
    private static func keys(after phrases: [String], in request: String) -> Set<String> {
        let requestWords = " " + request.lowercased() + " "
        var keys = Set<String>()
        for phrase in phrases {
            var searchRange = requestWords.startIndex..<requestWords.endIndex
            while let phraseRange = requestWords.range(of: phrase, range: searchRange) {
                let followingText = requestWords[phraseRange.upperBound...]
                let clause = followingText.split(separator: ",").first.map(String.init) ?? ""
                let clauseWords = clause.split { !$0.isLetter }.map(String.init)
                for word in clauseWords.prefix(5) {
                    if word == "and" || word == "add" || word == "but" { break }
                    if word.count >= 3, word != "the", word != "all", word != "any" {
                        keys.insert(String(word.prefix(4)))
                    }
                }
                searchRange = phraseRange.upperBound..<requestWords.endIndex
            }
        }
        return keys
    }

    /// The words of a subject that would show up in a request about it (first four letters of
    /// each longer word, so "dragons" matches "dragon").
    private static func keyWords(of subject: String) -> [String] {
        subject.lowercased()
            .split { !$0.isLetter }
            .filter { $0.count >= 3 }
            .map { String($0.prefix(4)) }
    }

    private static func requestMentions(_ part: String, in requestWords: String) -> Bool {
        (mentionWords[part] ?? []).contains { requestWords.contains($0) }
    }

    private static func requestNamesColor(_ color: GeneratedColor, in requestWords: String) -> Bool {
        color.spokenNames.contains { requestWords.contains($0) }
    }

    /// The color written right next to one of these words in the request, as in "pink confetti",
    /// "orange snow", or "make the leaves pink". Nil if the request doesn't put a color there.
    private static func colorWritten(next subjectKeys: [String], in request: String) -> GeneratedColor? {
        let words = request.lowercased().split { !$0.isLetter }.map(String.init)
        func color(at phrase: String) -> GeneratedColor? {
            GeneratedColor.allNamed.first { $0.spokenNames.contains(phrase) }
        }
        for (index, word) in words.enumerated() where subjectKeys.contains(where: { word.hasPrefix($0) }) {
            // Before the word: "pink confetti", "sky blue confetti".
            if index > 0, let before = color(at: words[index - 1]) { return before }
            if index > 1, let before = color(at: "\(words[index - 2]) \(words[index - 1])") { return before }
            // After the word: "leaves pink", "make the snow sky blue".
            if index + 1 < words.count, let after = color(at: words[index + 1]) { return after }
            if index + 2 < words.count, let after = color(at: "\(words[index + 1]) \(words[index + 2])") { return after }
        }
        return nil
    }

    /// Applies every color written next to a word ("pink confetti", "leaves pink") to that part.
    /// In a new scene, a color paired with one part also isn't allowed to spread to other parts;
    /// in a change, parts the request doesn't pair keep the colors they already had.
    private static func applyingWrittenColors(to settings: SceneSettings, request: String, isNewScene: Bool) -> SceneSettings {
        var colored = settings
        var pairedColors = Set<GeneratedColor>()
        func written(next keys: [String]) -> GeneratedColor? {
            let color = colorWritten(next: keys, in: request)
            if let color { pairedColors.insert(color) }
            return color
        }

        let snowColor = written(next: ["snow"])
        let rainColor = written(next: ["rain"])
        let fogColor = written(next: ["fog", "mist"])
        let skyColor = written(next: ["sky", "background"])
        let layerColors = settings.layers.map { layer in
            written(next: keyWords(of: layer.subject) + layer.builtIn.keywords)
        }

        // Parts without their own pairing can't borrow a color that belongs to another part.
        func resolved(_ modelColor: GeneratedColor, _ writtenColor: GeneratedColor?) -> GeneratedColor {
            writtenColor ?? (isNewScene && pairedColors.contains(modelColor) ? .natural : modelColor)
        }
        colored.snowColor = resolved(settings.snowColor, snowColor)
        colored.rainColor = resolved(settings.rainColor, rainColor)
        colored.fogColor = resolved(settings.fogColor, fogColor)
        for index in colored.layers.indices {
            colored.layers[index].color = resolved(settings.layers[index].color, layerColors[index])
        }

        if let skyColor {
            colored.skyColor = skyColor
            if colored.skyStrength == .none { colored.skyStrength = .subtle }
        } else if isNewScene, pairedColors.contains(settings.skyColor) {
            colored.skyColor = .natural
        }
        // A tint with no color isn't a tint.
        if colored.skyColor == .natural, !(request.lowercased().contains("night") || request.lowercased().contains("dark")) {
            colored.skyStrength = .none
        }
        // Night scenes get a dark sky unless the request names a sky color.
        let isNightScene = ["night", "midnight", "evening", "dark"].contains { request.lowercased().contains($0) }
        if isNightScene, skyColor == nil {
            colored.skyColor = .navy
            if colored.skyStrength == .none { colored.skyStrength = .subtle }
        }
        return colored
    }

    /// The first four letters of each word after "raining" or "rains", as in "raining tacos and cats",
    /// or nil if the request doesn't use that phrasing.
    private static func thingsRainingDown(in requestWords: String) -> Set<String>? {
        let words = requestWords.split { !$0.isLetter }.map(String.init)
        guard let index = words.firstIndex(where: { $0 == "raining" || $0 == "rains" }), index + 1 < words.count else {
            return nil
        }
        let fillerWords: Set<String> = ["and", "with", "while", "the", "down", "outside", "today", "tonight", "all",
                                        "day", "night", "hard", "heavily", "lightly", "softly", "again", "too", "also"]
        let followingWords = words[(index + 1)...].prefix(4).filter { $0.count >= 3 && !fillerWords.contains($0) }
        return followingWords.isEmpty ? nil : Set(followingWords.map { String($0.prefix(4)) })
    }

    private static let snowWords = ["snow", "blizzard", "flurr", "winter", "sleet"]
    private static let fogWords = ["fog", "mist", "haze", "hazy"]
    private static let lightningWords = ["lightning", "thunder", "storm"]

    private static func mentionsAny(_ keywords: [String], in requestWords: String) -> Bool {
        keywords.contains { requestWords.contains($0) }
    }

    /// The model's level when the request asks for this weather (at least medium), or none when it doesn't.
    private static func wanted(_ isRequested: Bool, modelLevel: Level) -> Level {
        isRequested ? (modelLevel == .none ? .medium : modelLevel) : .none
    }

    // MARK: Motion

    /// Words that ask for each kind of motion.
    private static let motionWords: [(GeneratedMotion, [String])] = [
        (.rise, ["rising", "rise", "floating up", "float up", "going up", "ascend"]),
        (.float, ["float", "hover", "hanging", "suspended"]),
        (.drift, ["flying", "fly ", "flies", "swim", "across", "sideways", "drift", "sailing", "zoom"]),
        (.twinkle, ["twinkl", "sparkl", "shimmer", "blink"]),
        (.wander, ["wander", "flutter", "buzz", "dancing", "bouncing", "roam"]),
        (.fall, ["fall", "falling", "raining", "drop", "pouring", "tumbl"]),
    ]

    /// Things that move their own way unless the request says otherwise.
    private static let naturalMotions: [(GeneratedMotion, [String])] = [
        (.rise, ["balloon", "lantern", "smoke"]),
        (.wander, ["butterfl", "bee", "moth", "firefl"]),
        (.drift, ["bird", "fish", "plane", "ufo", "kite", "cloud", "whale", "ship", "boat", "rocket", "ghost", "bat"]),
    ]

    /// The part of the request about a subject: the clause (split at commas, "and", "with",
    /// "while") that names it.
    private static func clause(about subjectKeys: [String], in requestWords: String) -> String? {
        requestWords
            .replacingOccurrences(of: " and ", with: ",")
            .replacingOccurrences(of: " with ", with: ",")
            .replacingOccurrences(of: " while ", with: ",")
            .split(separator: ",")
            .map { " \($0) " }
            .first { clause in subjectKeys.contains { clause.contains($0) } }
    }

    /// A motion the request asks for this subject, as in "floating hearts" or "make the pizza fall".
    private static func explicitMotion(for subject: String, in requestWords: String) -> GeneratedMotion? {
        guard let clause = clause(about: keyWords(of: subject), in: requestWords) else { return nil }
        return motionWords.first { _, words in words.contains { clause.contains($0) } }?.0
    }

    /// How a subject moves on its own, such as balloons rising or birds flying across.
    private static func naturalMotion(for subject: String) -> GeneratedMotion? {
        let subjectKeys = keyWords(of: subject)
        return naturalMotions.first { _, words in
            subjectKeys.contains { key in words.contains { $0.hasPrefix(key) || key.hasPrefix($0) } }
        }?.0
    }

    /// Emoji layers fall unless the request gives that thing another motion ("floating hearts",
    /// "birds flying across") or the thing naturally moves another way (balloons rise).
    private static func withRequestedMotions(_ layers: [GeneratedLayer], request requestWords: String, rainedThings: Set<String>) -> [GeneratedLayer] {
        layers.map { layer in
            guard layer.builtIn == .none else { return layer }
            var adjusted = layer
            if keyWords(of: layer.subject).contains(where: { rainedThings.contains($0) }) {
                adjusted.motion = .fall
            } else {
                adjusted.motion = explicitMotion(for: layer.subject, in: requestWords)
                    ?? naturalMotion(for: layer.subject)
                    ?? .fall
            }
            return adjusted
        }
    }

    /// Whether the request asks for real rain, beyond "raining something".
    private static func asksForWaterRain(_ requestWords: String) -> Bool {
        let words = requestWords.split { !$0.isLetter }.map(String.init)
        return words.contains { ["rain", "rainy", "raindrops", "rainfall", "drizzle", "storm", "stormy", "downpour", "showers"].contains($0) }
    }

    /// Keeps colors only where the request actually names that color, and keeps the background
    /// tint only if the request mentions the sky, time of day, or a mood.
    private func keepingOnlyNamedColorsAndSky(_ settings: SceneSettings, request: String) -> SceneSettings {
        let requestWords = request.lowercased()
        func checked(_ color: GeneratedColor) -> GeneratedColor {
            Self.requestNamesColor(color, in: requestWords) ? color : .natural
        }

        var guarded = settings
        guarded.snowColor = checked(settings.snowColor)
        guarded.rainColor = checked(settings.rainColor)
        guarded.fogColor = checked(settings.fogColor)
        guarded.layers = settings.layers.map { layer in
            var checkedLayer = layer
            checkedLayer.color = checked(layer.color)
            return checkedLayer
        }
        if !Self.requestMentions("sky", in: requestWords) {
            guarded.skyStrength = .none
        }
        if !Self.requestMentions("wind", in: requestWords) {
            guarded.wind = .calm
        }

        // Weather follows the request's words directly: what's mentioned is in, the rest is out.
        // "Raining tacos" means tacos fall, not water rain, unless rain is also asked for.
        let rainedThings = Self.thingsRainingDown(in: requestWords)
        let wantsRain = Self.asksForWaterRain(requestWords)
            || (rainedThings == nil && ["raining", "rains"].contains { requestWords.contains($0) })
        guarded.snow = Self.wanted(Self.mentionsAny(Self.snowWords, in: requestWords), modelLevel: guarded.snow)
        guarded.rain = Self.wanted(wantsRain, modelLevel: guarded.rain)
        guarded.fog = Self.wanted(Self.mentionsAny(Self.fogWords, in: requestWords), modelLevel: guarded.fog)
        guarded.lightning = Self.mentionsAny(Self.lightningWords, in: requestWords)

        guarded.layers = Self.withRequestedMotions(guarded.layers, request: requestWords, rainedThings: rainedThings ?? [])
        return Self.applyingWrittenColors(to: guarded, request: request, isNewScene: true)
    }

    // MARK: - Verification

    /// How weather parts are described when double-checking them against the request.
    private static let weatherDescriptions: [String: String] = [
        "snow": "falling snow",
        "rain": "rain",
        "fog": "fog or mist",
        "lightning": "lightning or a thunderstorm",
    ]

    /// Double-checks each element of a new scene that the request doesn't name outright, with one
    /// focused question per element (asked in parallel), and drops the ones the model can't justify.
    private func removingUnrequestedElements(from settings: SceneSettings, request: String) async -> SceneSettings {
        let requestWords = request.lowercased()

        // Weather is already decided by the request's words; only layers need double-checking.
        let weatherToCheck: [String] = []

        let layersToCheck = settings.layers.indices.filter { index in
            !Self.keyWords(of: settings.layers[index].subject).contains { requestWords.contains($0) }
        }

        let rejected = await withTaskGroup(of: (String, Bool).self) { group in
            for part in weatherToCheck {
                let description = Self.weatherDescriptions[part] ?? part
                group.addTask { (part, await self.requestImplies(description, request: request)) }
            }
            for index in layersToCheck {
                let subject = settings.layers[index].subject
                group.addTask { ("layer\(index)", await self.requestImplies(subject, request: request)) }
            }
            var rejectedParts = Set<String>()
            for await (part, isJustified) in group where !isJustified {
                rejectedParts.insert(part)
            }
            return rejectedParts
        }

        var verified = settings
        if rejected.contains("snow") { verified.snow = .none }
        if rejected.contains("rain") { verified.rain = .none }
        if rejected.contains("fog") { verified.fog = .none }
        if rejected.contains("lightning") { verified.lightning = false }
        verified.layers = settings.layers.enumerated()
            .filter { !rejected.contains("layer\($0.offset)") }
            .map(\.element)
        return verified
    }

    /// Asks the model one narrow question, with a short reason first: does the request call for this element?
    private func requestImplies(_ elementDescription: String, request: String) async -> Bool {
        do {
            let session = LanguageModelSession(instructions: """
                You check animated desktop scenes. Decide whether an element belongs in the scene \
                someone described. It belongs only if they asked for it or it is an obvious part of \
                that scene, like embers at a campfire. Elements that are merely possible do not belong, \
                like lightning at a campfire or leaves at a party.
                """)
            let response = try await session.respond(
                to: "Description: \"\(request)\". Element: \(elementDescription).",
                generating: ElementCheck.self,
                options: generationOptions
            )
            return response.content.isRequested
        } catch {
            // If the check fails, keep what the model originally chose.
            return true
        }
    }

    // MARK: - Changes

    /// Applies a generated change to the current settings, keeping everything it doesn't mention.
    private func applying(_ change: GeneratedSceneChange, to scene: SceneSettings, request: String) -> SceneSettings {
        let requestWords = request.lowercased()
        let mentionsWholeScene = Self.wholeSceneWords.contains { requestWords.contains($0) }
        let removed = Self.removedKeys(in: request)
        let reduced = Self.keys(after: Self.reductionWords, in: request)
        let increased = Self.keys(after: Self.increasePhrases, in: request).subtracting(removed)
        let asksForLess = Self.reductionWords.contains { requestWords.contains($0) }
        func mentions(_ part: String) -> Bool {
            mentionsWholeScene || Self.requestMentions(part, in: requestWords)
        }
        func isRemoved(_ part: String) -> Bool {
            !(Self.weatherKeys[part] ?? []).filter { removed.contains($0) }.isEmpty
        }
        func isNamed(_ part: String, in keys: Set<String>) -> Bool {
            !(Self.weatherKeys[part] ?? []).filter { keys.contains($0) }.isEmpty
        }
        func namesColor(_ color: GeneratedColor) -> Bool {
            color != .natural && Self.requestNamesColor(color, in: requestWords)
        }

        // Increases apply when the part is mentioned; reductions need words asking for less;
        // removals need the part named right after a removal phrase.
        func applied(_ levelChange: LevelChange, to level: Level, part: String) -> Level {
            // What the request literally says wins over the model's answer.
            if isRemoved(part) { return .none }
            // "Less snow" makes it lighter but keeps some; removing it takes a removal phrase.
            if isNamed(part, in: reduced) { return level == .none ? .none : heavierLevel(level.stepped(by: -1), .light) }
            if isNamed(part, in: increased) { return level == .none ? .medium : level.stepped(by: 1) }
            switch levelChange {
            case .keep: return level
            case .increase: return mentions(part) ? (level == .none ? .medium : level.stepped(by: 1)) : level
            case .decrease: return mentions(part) && asksForLess ? level.stepped(by: -1) : level
            case .remove: return level
            }
        }

        var updated = scene
        let newTitle = change.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty {
            updated.title = newTitle
        }
        updated.snow = applied(change.snow, to: scene.snow, part: "snow")
        updated.rain = applied(change.rain, to: scene.rain, part: "rain")
        updated.fog = applied(change.fog, to: scene.fog, part: "fog")
        if mentions("snow"), namesColor(change.snowColor) { updated.snowColor = change.snowColor }
        if mentions("rain"), namesColor(change.rainColor) { updated.rainColor = change.rainColor }
        if (change.wind != .weaker && change.wind != .calm) || mentions("wind") {
            updated.wind = Self.applied(change.wind, to: scene.wind)
        }

        switch change.lightning {
        case .keep: break
        case .turnOn: updated.lightning = true
        case .turnOff: if isRemoved("lightning") || mentions("lightning") && asksForLess { updated.lightning = false }
        }

        // The background only changes when the request talks about it.
        if mentions("sky") || namesColor(change.newSkyColor) && requestWords.contains("background") {
            if change.newSkyColor != .natural {
                updated.skyColor = change.newSkyColor
                if updated.skyStrength == .none {
                    updated.skyStrength = .subtle
                }
            }
            switch change.skyStrength {
            case .keep: break
            case .none: updated.skyStrength = .none
            case .subtle: updated.skyStrength = .subtle
            case .strong: updated.skyStrength = .strong
            }
        }

        // Removals apply exactly to what follows a removal phrase ("remove the confetti").
        if isRemoved("lightning") { updated.lightning = false }
        if isNamed("lightning", in: increased) { updated.lightning = true }
        if isRemoved("wind") { updated.wind = .calm }
        if isNamed("wind", in: increased) { updated.wind = Self.applied(.stronger, to: updated.wind) }
        if isNamed("wind", in: reduced) { updated.wind = Self.applied(.weaker, to: updated.wind) }
        func layerKeys(_ layer: GeneratedLayer) -> Set<String> {
            Set(Self.keyWords(of: layer.subject) + layer.builtIn.keywords.map { String($0.prefix(4)) })
        }
        updated.layers.removeAll { !layerKeys($0).isDisjoint(with: removed) }
        // "Make the pizza float" changes just that layer's motion.
        for index in updated.layers.indices where updated.layers[index].builtIn == .none {
            if let motion = Self.explicitMotion(for: updated.layers[index].subject, in: requestWords) {
                updated.layers[index].motion = motion
            }
        }

        // "More confetti" and "fewer dragons" adjust how many of an existing layer there are.
        for index in updated.layers.indices {
            let keys = layerKeys(updated.layers[index])
            if !keys.isDisjoint(with: reduced) {
                updated.layers[index].amount = heavierLevel(updated.layers[index].amount.stepped(by: -1), .light)
            } else if !keys.isDisjoint(with: increased) {
                updated.layers[index].amount = updated.layers[index].amount.stepped(by: 1)
            }
        }

        // Additions replace a matching layer (same effect, emoji, or subject) or are added at the end.
        // Only things the request names can be added.
        let namedAdditions = change.layersToAdd.filter { addition in
            let additionKeys = Self.keyWords(of: addition.subject)
                + BuiltInEffect.matching(addition.subject).keywords.map { String($0.prefix(4)) }
            let isNamed = additionKeys.contains { requestWords.contains($0) }
            let isBeingRemoved = additionKeys.contains { removed.contains($0) }
            return addition.amount != .none && isNamed && !isBeingRemoved
        }
        for addition in namedAdditions {
            var newLayer = addition
            if BuiltInEffect.matching(addition.subject) == .none {
                newLayer.motion = Self.explicitMotion(for: addition.subject, in: requestWords)
                    ?? Self.naturalMotion(for: addition.subject)
                    ?? .fall
            }
            if !namesColor(addition.color) {
                newLayer.color = .natural
            }
            let additionWords = Set(Self.keyWords(of: addition.subject))
            if let matchIndex = updated.layers.firstIndex(where: { layer in
                (layer.builtIn != .none && layer.builtIn == addition.builtIn)
                    || (layer.builtIn == .none && layer.emoji == addition.emoji)
                    || !Set(Self.keyWords(of: layer.subject)).isDisjoint(with: additionWords)
            }) {
                // Keep the old color and motion unless the request asks for new ones.
                if newLayer.color == .natural {
                    newLayer.color = updated.layers[matchIndex].color
                }
                if Self.explicitMotion(for: addition.subject, in: requestWords) == nil {
                    newLayer.motion = updated.layers[matchIndex].motion
                }
                updated.layers[matchIndex] = newLayer
            } else {
                updated.layers.append(newLayer)
            }
        }
        if updated.layers.count > maximumLayerCount {
            updated.layers.removeFirst(updated.layers.count - maximumLayerCount)
        }
        return Self.applyingWrittenColors(to: updated, request: request, isNewScene: false)
    }

    /// Steps the wind stronger or weaker, keeping its direction, or sets a new direction.
    private static func applied(_ windChange: WindChange, to wind: WindLevel) -> WindLevel {
        switch windChange {
        case .keep: wind
        case .calm: .calm
        case .blowLeft: wind == .strongRight || wind == .strongLeft ? .strongLeft : .breezeLeft
        case .blowRight: wind == .strongRight || wind == .strongLeft ? .strongRight : .breezeRight
        case .stronger:
            switch wind {
            case .calm: .breezeRight
            case .breezeLeft, .strongLeft: .strongLeft
            case .breezeRight, .strongRight: .strongRight
            }
        case .weaker:
            switch wind {
            case .calm, .breezeLeft, .breezeRight: .calm
            case .strongLeft: .breezeLeft
            case .strongRight: .breezeRight
            }
        }
    }

    // MARK: - Building the scene

    /// Converts settings into what the overlays show. Built-in layers use their own renderers;
    /// everything else becomes an emoji layer.
    private func makeWeather(from settings: SceneSettings, text: String) -> DescribedWeather {
        let scene = settings
        var ambientLayers: [AmbientLayer] = []
        var customLayers: [CustomLayer] = []

        for layer in settings.layers where layer.amount != .none {
            if let ambientKind = layer.builtIn.ambientKind {
                guard !ambientLayers.contains(where: { $0.kind == ambientKind }) else { continue }
                let isTooDarkToGlow = Self.glows(ambientKind) && layer.color.isTooDarkToGlow
                ambientLayers.append(AmbientLayer(
                    kind: ambientKind,
                    amount: CGFloat(layer.amount.amount),
                    color: isTooDarkToGlow ? nil : layer.color.nsColor
                ))
                continue
            }

            let emoji = Self.validatedEmoji(layer.emoji) ?? "✨"
            guard customLayers.count < CustomParticleLayer.maximumLayerCount else { continue }
            customLayers.append(CustomLayer(
                emoji: emoji,
                color: layer.color.nsColor,
                motion: layer.motion.customMotion,
                amount: CGFloat(layer.amount.amount),
                size: layer.size.points
            ))
        }

        let snowIntensity = CGFloat(scene.snow.amount)
        let effect = WeatherEffect(
            snowIntensity: snowIntensity,
            rainIntensity: CGFloat(scene.rain.amount),
            windDrift: CGFloat(scene.wind.drift),
            fogAmount: CGFloat(scene.fog.amount),
            fogColor: scene.fogColor == .white ? nil : scene.fogColor.nsColor,
            hasLightning: scene.lightning,
            isMelting: snowIntensity == 0,
            ambientLayers: ambientLayers,
            snowColor: scene.snowColor == .white ? nil : scene.snowColor.nsColor,
            rainColor: scene.rainColor.nsColor,
            customLayers: customLayers
        )
        let skyTint = SkyTint(
            color: scene.skyColor.nsColor ?? SkyTint.nightColor,
            strength: CGFloat(scene.skyStrength.strength)
        )
        let title = scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return DescribedWeather(
            text: text,
            title: title.isEmpty ? text : title,
            summary: Self.summary(of: scene),
            effect: effect,
            skyTint: skyTint,
            settings: scene
        )
    }

    /// A one-line list of what's in a scene, such as "light snow · 🐉 pink, falling · pink background".
    private static func summary(of scene: SceneSettings) -> String {
        func colored(_ name: String, _ color: GeneratedColor) -> String {
            color == .natural ? name : "\(name) (\(color))"
        }
        var parts: [String] = []
        if scene.snow != .none { parts.append(colored("\(scene.snow) snow", scene.snowColor)) }
        if scene.rain != .none { parts.append(colored("\(scene.rain) rain", scene.rainColor)) }
        if scene.lightning { parts.append("lightning") }
        if scene.fog != .none { parts.append(colored("\(scene.fog) fog", scene.fogColor)) }
        if scene.wind != .calm { parts.append("windy") }
        for layer in scene.layers where layer.amount != .none {
            let look = layer.builtIn == .none ? (validatedEmoji(layer.emoji) ?? "✨") : "\(layer.builtIn)"
            let colorText = layer.color == .natural ? "" : " \(layer.color)"
            parts.append("\(look)\(colorText), \(layer.motion)")
        }
        if scene.skyStrength != .none { parts.append("\(scene.skyColor) background") }
        return parts.isEmpty ? String(localized: "Clear") : parts.joined(separator: " · ")
    }

    /// The first emoji in the model's answer, or nil if it didn't give one.
    private static func validatedEmoji(_ text: String) -> String? {
        guard let firstCharacter = text.trimmingCharacters(in: .whitespaces).first else { return nil }
        let isEmoji = firstCharacter.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0xFF)
        }
        return isEmoji ? String(firstCharacter) : nil
    }

    /// Effects drawn as light, which disappear in dark colors.
    private static func glows(_ kind: AmbientKind) -> Bool {
        switch kind {
        case .fireflies, .embers, .stars, .dust, .shootingStars, .aurora: true
        case .leaves, .petals, .confetti, .bubbles: false
        }
    }

    // MARK: - Keyword fallback

    /// Recognizes common words when the on-device model isn't available.
    private static func keywordScene(for description: String) -> GeneratedScene {
        let words = description.lowercased()
        func mentions(_ keywords: String...) -> Bool {
            keywords.contains { words.contains($0) }
        }

        let isStormy = mentions("storm", "thunder", "lightning")
        let strength: Level =
            if mentions("blizzard", "heavy", "pouring", "downpour") || isStormy { .heavy }
            else if mentions("light", "gentle", "soft", "cozy", "flurr", "drizzle") { .light }
            else { .medium }

        // Built-in effects, then a few common things drawn as emoji.
        let builtInKeywords: [(BuiltInEffect, [String], GeneratedMotion)] = [
            (.leaves, ["autumn", "fall ", "leaves", "leaf"], .fall),
            (.petals, ["petal", "blossom", "spring", "sakura", "cherry"], .fall),
            (.confetti, ["confetti", "party", "celebrat", "birthday", "new year"], .fall),
            (.fireflies, ["firefl"], .wander),
            (.embers, ["ember", "campfire", "fireplace", "bonfire"], .rise),
            (.bubbles, ["bubble", "underwater"], .rise),
            (.stars, ["star", "starry"], .twinkle),
            (.dust, ["dust", "sunbeam", "haze", "dreamy"], .float),
            (.aurora, ["aurora", "northern light"], .float),
            (.shootingStars, ["shooting star", "meteor", "wish"], .fall),
        ]
        let emojiKeywords: [(String, [String], GeneratedMotion)] = [
            ("💖", ["heart", "love"], .rise), ("🎈", ["balloon"], .rise), ("🦋", ["butterfl"], .wander),
            ("🐱", ["cat"], .fall), ("🐶", ["dog"], .fall), ("🐉", ["dragon"], .fall), ("🍕", ["pizza"], .fall),
            ("🎃", ["pumpkin", "halloween"], .float), ("👻", ["ghost", "spooky"], .float), ("🐟", ["fish"], .drift),
            ("🐦", ["bird"], .drift), ("🎵", ["music", "note"], .rise), ("💸", ["money", "cash"], .fall),
            ("🍩", ["donut", "doughnut"], .fall), ("🌸", ["flower"], .fall),
        ]

        var layers = builtInKeywords
            .filter { _, keywords, _ in keywords.contains { words.contains($0) } }
            .map { effect, _, motion in
                GeneratedLayer(subject: effect.keywords.first ?? "\(effect)", builtIn: effect, emoji: "✨", color: .natural,
                               motion: motion, amount: .medium, size: .medium)
            }
        layers += emojiKeywords
            .filter { _, keywords, _ in keywords.contains { words.contains($0) } }
            .map { emoji, keywords, motion in
                GeneratedLayer(subject: keywords[0], builtIn: .none, emoji: emoji, color: .natural,
                               motion: motion, amount: .medium, size: .medium)
            }

        let (skyColor, skyStrength): (GeneratedColor, TintLevel) =
            if mentions("night", "evening", "midnight", "dark") { (.navy, .strong) }
            else if mentions("sunset", "dusk", "golden", "cozy", "warm") { (.amber, .subtle) }
            else if mentions("pink", "dreamy") { (.pink, .subtle) }
            else { (.natural, .none) }

        let wind: WindLevel =
            if mentions("blizzard", "gale", "gust") { .strongRight }
            else if mentions("wind", "blustery", "breez") || isStormy { .breezeRight }
            else { .calm }

        return GeneratedScene(
            title: description.capitalized,
            snow: mentions("snow", "blizzard", "flurr", "winter") ? strength : .none,
            snowColor: .natural,
            rain: isStormy || mentions("rain", "drizzle", "shower", "pour", "wet") ? strength : .none,
            rainColor: .natural,
            wind: wind,
            fog: mentions("fog", "mist", "haze") ? .heavy : .none,
            fogColor: .natural,
            lightning: isStormy,
            layers: Array(layers.prefix(4)),
            skyColor: skyColor,
            skyStrength: skyStrength
        )
    }
}

/// Whichever of two levels is heavier.
private func heavierLevel(_ first: Level, _ second: Level) -> Level {
    first.amount >= second.amount ? first : second
}
