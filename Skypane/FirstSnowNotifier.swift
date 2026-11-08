//
//  FirstSnowNotifier.swift
//  Skypane
//

import Foundation
import UserNotifications
import os

/// Sends one notification when live weather first turns to snow each winter.
/// Permission is asked at that moment, so the prompt shows up with a reason.
final class FirstSnowNotifier {
    /// The winter in which the first-snow notification was last sent.
    private let lastNotifiedWinterKey = "lastFirstSnowWinter"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skypane", category: "Notifications")

    /// Notifies if it's snowing and this winter hasn't had a first-snow notification yet.
    func checkForFirstSnow(report: WeatherReport, conditionText: String, date: Date, latitude: Double?) async {
        guard report.condition.isSnow || report.snowfallPerHour > 0 else { return }

        let winter = Self.winterIdentifier(for: date, latitude: latitude)
        guard UserDefaults.standard.integer(forKey: lastNotifiedWinterKey) != winter else { return }
        // Mark it first, so a slow or denied permission prompt never leads to repeats.
        UserDefaults.standard.set(winter, forKey: lastNotifiedWinterKey)

        let notificationCenter = UNUserNotificationCenter.current()
        do {
            guard try await notificationCenter.requestAuthorization(options: [.alert, .sound]) else { return }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "First snow of the season")
            content.body = String(localized: "It's snowing where you are: \(conditionText).")
            content.sound = .default

            let request = UNNotificationRequest(identifier: "first-snow-\(winter)", content: content, trigger: nil)
            try await notificationCenter.add(request)
        } catch {
            logger.error("First-snow notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Identifies a winter by the year it starts in. Northern winters span the new year, so they
    /// start counting in July; southern winters fall within one calendar year.
    private static func winterIdentifier(for date: Date, latitude: Double?) -> Int {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let isSouthernHemisphere = (latitude ?? 0) < 0
        return isSouthernHemisphere || month >= 7 ? year : year - 1
    }
}
