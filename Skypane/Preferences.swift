//
//  Preferences.swift
//  Skypane
//

import Foundation

/// Choices from the Settings window, saved between launches.
struct Preferences: Codable, Equatable {
    /// How much falls and floats, from 0.3 (a little) to 1.5 (a lot). 1 is the standard amount.
    var effectAmount: Double = 1
    var showsLightningFlashes = true
    var darkensDesktopAtNight = true
    var showsSeasonalExtras = true
    var pilesSnowOnWindows = true
    var showsDockEffects = true
    var cursorInteracts = true
    var pausesInFullScreen = true
    var pausesOnLowBattery = true
    var notifiesFirstSnow = true

    private static let storageKey = "preferences"

    /// The saved preferences, or the defaults if none are saved (or they can't be read).
    static func load() -> Preferences {
        guard let savedData = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(Preferences.self, from: savedData)
        else { return Preferences() }
        return saved
    }

    func save() {
        guard let encoded = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.storageKey)
    }

    // Decoding fills in defaults for anything missing, so new settings in later versions keep working.
    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        effectAmount = try container.decodeIfPresent(Double.self, forKey: .effectAmount) ?? defaults.effectAmount
        showsLightningFlashes = try container.decodeIfPresent(Bool.self, forKey: .showsLightningFlashes) ?? defaults.showsLightningFlashes
        darkensDesktopAtNight = try container.decodeIfPresent(Bool.self, forKey: .darkensDesktopAtNight) ?? defaults.darkensDesktopAtNight
        showsSeasonalExtras = try container.decodeIfPresent(Bool.self, forKey: .showsSeasonalExtras) ?? defaults.showsSeasonalExtras
        pilesSnowOnWindows = try container.decodeIfPresent(Bool.self, forKey: .pilesSnowOnWindows) ?? defaults.pilesSnowOnWindows
        showsDockEffects = try container.decodeIfPresent(Bool.self, forKey: .showsDockEffects) ?? defaults.showsDockEffects
        cursorInteracts = try container.decodeIfPresent(Bool.self, forKey: .cursorInteracts) ?? defaults.cursorInteracts
        pausesInFullScreen = try container.decodeIfPresent(Bool.self, forKey: .pausesInFullScreen) ?? defaults.pausesInFullScreen
        pausesOnLowBattery = try container.decodeIfPresent(Bool.self, forKey: .pausesOnLowBattery) ?? defaults.pausesOnLowBattery
        notifiesFirstSnow = try container.decodeIfPresent(Bool.self, forKey: .notifiesFirstSnow) ?? defaults.notifiesFirstSnow
    }
}
