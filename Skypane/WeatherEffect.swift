//
//  WeatherEffect.swift
//  Skypane
//

import Foundation
import AppKit

/// A readable weather condition, from a WMO weather code.
enum WeatherCondition: Equatable {
    case clear, partlyCloudy, overcast, fog
    case drizzle, freezingRain, lightRain, rain, heavyRain, rainShowers
    case lightSnow, snow, heavySnow, snowShowers
    case thunderstorm

    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .freezingRain
        case 61: self = .lightRain
        case 63: self = .rain
        case 65: self = .heavyRain
        case 80, 81, 82: self = .rainShowers
        case 71, 77: self = .lightSnow
        case 73: self = .snow
        case 75: self = .heavySnow
        case 85, 86: self = .snowShowers
        case 95, 96, 99: self = .thunderstorm
        default: self = .overcast
        }
    }

    var displayName: String {
        switch self {
        case .clear: String(localized: "Clear")
        case .partlyCloudy: String(localized: "Partly Cloudy")
        case .overcast: String(localized: "Cloudy")
        case .fog: String(localized: "Fog")
        case .drizzle: String(localized: "Drizzle")
        case .freezingRain: String(localized: "Freezing Rain")
        case .lightRain: String(localized: "Light Rain")
        case .rain: String(localized: "Rain")
        case .heavyRain: String(localized: "Heavy Rain")
        case .rainShowers: String(localized: "Rain Showers")
        case .lightSnow: String(localized: "Light Snow")
        case .snow: String(localized: "Snow")
        case .heavySnow: String(localized: "Heavy Snow")
        case .snowShowers: String(localized: "Snow Showers")
        case .thunderstorm: String(localized: "Thunderstorm")
        }
    }

    var isSnow: Bool {
        switch self {
        case .lightSnow, .snow, .heavySnow, .snowShowers: true
        default: false
        }
    }

    /// Whether anything is falling (rain, drizzle, snow, or a storm).
    var isPrecipitating: Bool {
        switch self {
        case .clear, .partlyCloudy, .overcast, .fog: false
        default: true
        }
    }

    /// SF Symbol for the menu bar.
    func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max" : "moon.stars"
        case .partlyCloudy: isDay ? "cloud.sun" : "cloud.moon"
        case .overcast: "cloud"
        case .fog: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        case .freezingRain: "cloud.sleet"
        case .lightRain, .rain, .rainShowers: "cloud.rain"
        case .heavyRain: "cloud.heavyrain"
        case .lightSnow, .snow, .heavySnow, .snowShowers: "cloud.snow"
        case .thunderstorm: "cloud.bolt.rain"
        }
    }
}

/// Decorative effects that can be layered over the weather.
enum AmbientKind: CaseIterable, Equatable {
    case leaves, petals, confetti, fireflies, embers, bubbles, stars, dust, aurora, shootingStars
}

/// One decorative effect with how much of it to show and, optionally, its color.
struct AmbientLayer: Equatable {
    var kind: AmbientKind
    /// From 0 (a few) to 1 (lots).
    var amount: CGFloat
    /// Nil uses the effect's natural colors (autumn leaves, pink petals, warm embers, and so on).
    var color: NSColor?
}

/// How an emoji layer moves across the screen.
enum CustomMotion: Equatable {
    /// Tumbles down from the top.
    case fall
    /// Drifts up from the bottom and fades out.
    case rise
    /// Hangs in the air, drifting slowly.
    case float
    /// Travels sideways across the screen with a gentle bob.
    case drift
    /// Stays in place, fading in and out.
    case twinkle
    /// Wanders around at random.
    case wander
}

/// A layer of anything that isn't a built-in effect, drawn as an emoji (for example 🐉 or 🍕).
struct CustomLayer: Equatable {
    var emoji: String
    /// Nil keeps the emoji's own colors; otherwise the emoji is recolored, keeping its shading.
    var color: NSColor?
    var motion: CustomMotion
    /// From 0 (a few) to 1 (lots).
    var amount: CGFloat
    /// Emoji size in points.
    var size: CGFloat
}

/// Everything the overlays need to render: live weather, a preview, or a typed scene.
struct WeatherEffect: Equatable {
    /// How heavy the snow is, from 0 (none) to 1 (blizzard).
    var snowIntensity: CGFloat
    /// How heavy the rain is, from 0 (none) to 1 (downpour). Snow and rain can fall together.
    var rainIntensity: CGFloat
    /// Sideways push from the wind, from -1 (strong, blowing left) to 1 (strong, blowing right).
    var windDrift: CGFloat
    /// How thick the fog is, from 0 (none) to 1 (dense).
    var fogAmount: CGFloat
    /// Nil for ordinary white fog.
    var fogColor: NSColor?
    var hasLightning: Bool
    /// Above freezing, so piled snow slowly melts.
    var isMelting: Bool
    /// Decorative effects on top, such as leaves, fireflies, or an aurora.
    var ambientLayers: [AmbientLayer]
    /// Nil for white snow.
    var snowColor: NSColor?
    /// Nil for ordinary rain.
    var rainColor: NSColor?
    /// Anything else, drawn as emoji layers.
    var customLayers: [CustomLayer]

    /// Gentle snow shown before live weather is available, or if it can't be loaded.
    static let fallbackSnow = WeatherEffect(snowIntensity: 0.6)

    /// Wind speed (km/h) at which particles get the strongest tilt.
    private static let strongWindSpeed: Double = 50

    init(snowIntensity: CGFloat = 0, rainIntensity: CGFloat = 0, windDrift: CGFloat = 0,
         fogAmount: CGFloat = 0, fogColor: NSColor? = nil, hasLightning: Bool = false,
         isMelting: Bool = false, ambientLayers: [AmbientLayer] = [],
         snowColor: NSColor? = nil, rainColor: NSColor? = nil, customLayers: [CustomLayer] = []) {
        self.snowIntensity = snowIntensity
        self.rainIntensity = rainIntensity
        self.windDrift = windDrift
        self.fogAmount = fogAmount
        self.fogColor = fogColor
        self.hasLightning = hasLightning
        self.isMelting = isMelting
        self.ambientLayers = ambientLayers
        self.snowColor = snowColor
        self.rainColor = rainColor
        self.customLayers = customLayers
    }

    /// Turns a weather report into realistic effect settings, with seasonal extras for the given time and place.
    init(report: WeatherReport, date: Date, latitude: Double?) {
        let condition = report.condition

        // Precipitation type comes from the weather code, with measured snowfall as a tiebreaker.
        let isSnow: Bool
        let isPrecipitating: Bool
        switch condition {
        case .lightSnow, .snow, .heavySnow, .snowShowers:
            isSnow = true
            isPrecipitating = true
        case .drizzle, .freezingRain, .lightRain, .rain, .heavyRain, .rainShowers, .thunderstorm:
            isSnow = report.snowfallPerHour > 0 && report.temperatureCelsius <= 0
            isPrecipitating = true
        case .clear, .partlyCloudy, .overcast, .fog:
            isSnow = false
            isPrecipitating = false
        }

        // Intensity from the measured rate (square root so light precipitation is still visible).
        // If the model reports a precipitating code but no rate, fall back to the code's strength.
        let measuredIntensity = isSnow
            ? (report.snowfallPerHour / 3).squareRoot()
            : (report.precipitationPerHour / 10).squareRoot()
        let rawIntensity = measuredIntensity > 0 ? measuredIntensity : Self.intensity(forCode: report.weatherCode)
        let intensity = isPrecipitating ? CGFloat(min(max(rawIntensity, 0.15), 1)) : 0
        snowIntensity = isSnow ? intensity : 0
        rainIntensity = isSnow ? 0 : intensity

        // Only the east–west part of the wind tilts particles. Wind direction is where it comes
        // from, so a west wind (270°) blows toward the right of the screen.
        let directionRadians = report.windDirection * .pi / 180
        let windStrength = min(report.windSpeed / Self.strongWindSpeed, 1)
        windDrift = CGFloat(-sin(directionRadians) * windStrength)

        // Fog from the weather code, thickened by low visibility (which also adds mist to rain).
        let visibilityFog = report.visibility.map { min(max((2000 - $0) / 1800, 0), 1) } ?? 0
        fogAmount = CGFloat(condition == .fog ? max(0.5, visibilityFog) : visibilityFog * 0.8)
        fogColor = nil

        hasLightning = condition == .thunderstorm
        isMelting = report.temperatureCelsius > 0.5
        ambientLayers = SeasonalEffect(date: date, latitude: latitude, report: report).ambientLayers
        snowColor = nil
        rainColor = nil
        customLayers = []
    }

    /// SF Symbol that best matches what's on screen, for the menu bar.
    func symbolName(isNight: Bool) -> String {
        if hasLightning { return "cloud.bolt.rain" }
        if snowIntensity > 0, rainIntensity > 0 { return "cloud.sleet" }
        if snowIntensity > 0 { return "cloud.snow" }
        if rainIntensity > 0 { return "cloud.rain" }
        if fogAmount >= 0.5 { return "cloud.fog" }
        if !customLayers.isEmpty { return "wand.and.stars" }
        switch ambientLayers.first?.kind {
        case .leaves: return "leaf"
        case .petals: return "camera.macro"
        case .confetti: return "party.popper"
        case .fireflies, .dust: return "sparkles"
        case .embers: return "flame"
        case .bubbles: return "bubbles.and.sparkles"
        case .stars, .shootingStars, .aurora: return "moon.stars"
        case nil: return isNight ? "moon.stars" : "sun.max"
        }
    }

    /// Typical strength of a WMO code, for when no measured rate is available.
    private static func intensity(forCode code: Int) -> Double {
        switch code {
        case 51, 56, 61, 66, 71, 77, 80, 85: 0.3
        case 53, 63, 73, 81, 95: 0.55
        case 55, 57, 65, 67, 75, 82, 86, 96, 99: 0.85
        default: 0
        }
    }
}

/// Realistic extras for live weather, depending on the time of year.
enum SeasonalEffect: Equatable {
    case none
    /// Autumn daytime: leaves tumbling down the desktop.
    case fallingLeaves
    /// Warm summer evenings: fireflies drifting and blinking.
    case fireflies

    /// Lowest temperature (°C) at which fireflies come out.
    private static let fireflyMinimumTemperature: Double = 15

    /// Picks the seasonal extra for a moment and place. Seasons flip in the southern hemisphere;
    /// without a known latitude, the northern hemisphere is assumed.
    init(date: Date, latitude: Double?, report: WeatherReport) {
        let month = Calendar.current.component(.month, from: date)
        let isSouthernHemisphere = (latitude ?? 0) < 0
        let autumnMonths: Set<Int> = isSouthernHemisphere ? [3, 4, 5] : [9, 10, 11]
        let summerMonths: Set<Int> = isSouthernHemisphere ? [12, 1, 2] : [6, 7, 8]

        let isDry = report.precipitationPerHour <= 0 && report.snowfallPerHour <= 0 && !report.condition.isPrecipitating

        // Rain and snow take priority: leaves and fireflies only show in dry weather.
        if autumnMonths.contains(month), report.isDay, isDry {
            self = .fallingLeaves
        } else if summerMonths.contains(month), !report.isDay, isDry,
                  report.temperatureCelsius >= Self.fireflyMinimumTemperature {
            self = .fireflies
        } else {
            self = .none
        }
    }

    var ambientLayers: [AmbientLayer] {
        switch self {
        case .none: []
        case .fallingLeaves: [AmbientLayer(kind: .leaves, amount: 0.6, color: nil)]
        case .fireflies: [AmbientLayer(kind: .fireflies, amount: 0.6, color: nil)]
        }
    }
}

/// A color wash over the desktop wallpaper: night darkening for live weather, or any mood color for typed scenes.
struct SkyTint: Equatable {
    var color: NSColor
    /// From 0 (no tint) to 1 (strongest).
    var strength: CGFloat

    static let none = SkyTint(color: nightColor, strength: 0)
    /// Deep blue used to darken the desktop at night.
    static let nightColor = NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.2, alpha: 1)

    /// Length of the fade into and out of night on either side of sunrise and sunset.
    private static let twilightDuration: TimeInterval = 40 * 60

    init(color: NSColor, strength: CGFloat) {
        self.color = color
        self.strength = strength
    }

    /// Night darkening for a moment in time, using that day's sunrise and sunset (or just day/night if they're unknown).
    init(date: Date, report: WeatherReport) {
        guard let sunrise = report.sunrise, let sunset = report.sunset else {
            self.init(color: Self.nightColor, strength: report.isDay ? 0 : 1)
            return
        }

        let twilight = Self.twilightDuration
        let timeSinceSunrise = date.timeIntervalSince(sunrise)
        let timeUntilSunset = sunset.timeIntervalSince(date)

        // Daylight ramps up across sunrise and down across sunset.
        let morningLight = min(max((timeSinceSunrise + twilight) / (2 * twilight), 0), 1)
        let eveningLight = min(max((timeUntilSunset + twilight) / (2 * twilight), 0), 1)
        let daylight = min(morningLight, eveningLight)

        self.init(color: Self.nightColor, strength: CGFloat(1 - daylight))
    }
}

/// Fixed weather to preview instead of live conditions, for testing effects.
enum WeatherPreview: String, CaseIterable, Identifiable {
    case clear, lightSnow, heavySnow, rain, thunderstorm, fog, autumnLeaves, fireflies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: String(localized: "Clear")
        case .lightSnow: String(localized: "Light Snow")
        case .heavySnow: String(localized: "Heavy Snow, Windy")
        case .rain: String(localized: "Rain")
        case .thunderstorm: String(localized: "Thunderstorm")
        case .fog: String(localized: "Fog")
        case .autumnLeaves: String(localized: "Autumn Leaves")
        case .fireflies: String(localized: "Summer Fireflies")
        }
    }

    /// The effect to show.
    var effect: WeatherEffect {
        switch self {
        case .clear: WeatherEffect(isMelting: true)
        case .lightSnow: WeatherEffect(snowIntensity: 0.3, windDrift: 0.1)
        case .heavySnow: WeatherEffect(snowIntensity: 1, windDrift: 0.6, fogAmount: 0.2)
        case .rain: WeatherEffect(rainIntensity: 0.6, windDrift: -0.3, fogAmount: 0.15, isMelting: true)
        case .thunderstorm: WeatherEffect(rainIntensity: 0.9, windDrift: 0.5, fogAmount: 0.2, hasLightning: true, isMelting: true)
        case .fog: WeatherEffect(windDrift: 0.1, fogAmount: 0.9)
        case .autumnLeaves: WeatherEffect(windDrift: 0.3, isMelting: true, ambientLayers: SeasonalEffect.fallingLeaves.ambientLayers)
        case .fireflies: WeatherEffect(isMelting: true, ambientLayers: SeasonalEffect.fireflies.ambientLayers)
        }
    }

    /// A fixed sky tint for previews that depend on time of day, or nil to follow the real sun.
    var skyTint: SkyTint? {
        switch self {
        case .fireflies: SkyTint(color: SkyTint.nightColor, strength: 1)
        case .autumnLeaves: SkyTint.none
        default: nil
        }
    }

    /// SF Symbol for the menu bar while previewing.
    var symbolName: String {
        effect.symbolName(isNight: (skyTint?.strength ?? 0) > 0.5)
    }
}
