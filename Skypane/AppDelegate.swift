//
//  AppDelegate.swift
//  Skypane
//

import AppKit
import Combine
import CoreLocation
import ServiceManagement
import os

/// What the overlays are showing: real weather, the typed scene, or a preview.
enum WeatherSource: Hashable {
    case live
    case custom
    case preview(WeatherPreview)
}

/// Where live weather stands, for the menu.
enum WeatherStatus: Equatable {
    case locating
    case loading
    case current(WeatherReport)
    case locationDenied
    case unavailable
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Whether the weather is currently paused. Changing it updates every overlay.
    @Published var isPaused = false {
        didSet { applyPausedState() }
    }

    /// Whether Accessibility permission lets snow fit the Dock exactly (rather than an estimate).
    @Published private(set) var isDockFitExact = false

    /// Live weather state shown in the menu.
    @Published private(set) var weatherStatus: WeatherStatus = .locating

    /// What's showing. Picking one in the menu (or typing a scene) switches every screen.
    @Published var weatherSource: WeatherSource = .live {
        didSet {
            // Custom can only be chosen once a scene exists.
            if weatherSource == .custom, describedWeather == nil {
                weatherSource = .live
            }
            applyWeatherEffect()
            applySkyTint()
        }
    }

    /// Choices from the Settings window. Changing them saves and applies them right away.
    @Published var preferences = Preferences.load() {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            applyPreferences()
        }
    }

    /// Whether Skypane opens when you log in.
    @Published var launchesAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchesAtLogin != oldValue else { return }
            updateLoginItem()
        }
    }

    /// Whether effects are paused to save power (Low Power Mode, or a low battery).
    @Published private(set) var isPausedForPower = false

    /// macOS accessibility display settings that tone effects down.
    @Published private(set) var reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published private(set) var reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    /// The most recent typed scene. It stays available in the menu after switching away.
    @Published private(set) var describedWeather: DescribedWeather?
    /// Whether a typed description is being turned into weather.
    @Published private(set) var isDescribingWeather = false

    /// How often app window positions are re-read: often while snow or rain can land or snow is
    /// piled up, and less often otherwise (still enough to notice full-screen apps).
    private let fastWindowPollingInterval: Duration = .milliseconds(100)
    private let slowWindowPollingInterval: Duration = .milliseconds(500)
    /// Whether the weather on screen right now has snow or rain falling.
    private var isPrecipitationShowing = true
    /// How often the sky tint is recalculated.
    private let skyTintInterval: Duration = .seconds(60)
    /// How often live weather is refreshed, and how soon to retry after a failure.
    private let weatherRefreshInterval: TimeInterval = 15 * 60
    private let weatherRetryInterval: TimeInterval = 2 * 60

    /// One pair of overlay windows per connected screen.
    private var screenOverlays: [ScreenOverlay] = []

    private let windowTracker = WindowTracker()
    private let dockEstimator = DockEstimator()
    private let dockEstimateInterval: TimeInterval = 1
    private var estimatedDockFrame: CGRect?
    private var nextDockEstimate = Date.distantPast
    private let locationProvider = LocationProvider()
    private let weatherClient = OpenMeteoClient()
    private let firstSnowNotifier = FirstSnowNotifier()
    private let weatherDescriber = WeatherDescriber()
    private let powerMonitor = PowerMonitor()
    private var systemObservers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Skypane", category: "Weather")

    private var latestReport: WeatherReport?
    private var lastKnownCoordinate: CLLocationCoordinate2D?
    private var windowPollingTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOtherCopies()
        screenOverlays = NSScreen.screens.map { ScreenOverlay(screen: $0) }
        applyPreferences()
        observeSystemChanges()
        updatePowerState()
        startWindowPolling()
        startWeatherUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowPollingTask?.cancel()
        weatherTask?.cancel()
        for observer in systemObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Only one Skypane should run at a time, or weather draws twice. The newest copy takes over.
    private func quitOtherCopies() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let otherCopies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0 != NSRunningApplication.current }
        for otherCopy in otherCopies {
            otherCopy.terminate()
        }
    }

    // MARK: - System changes

    /// Watches for power and accessibility changes, and for screens being added or removed.
    /// The observers run on the main queue, so they can update the overlays directly.
    private func observeSystemChanges() {
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePowerState() }
        })
        systemObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAccessibilitySettings() }
        })
        systemObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        })
    }

    /// Pauses effects in Low Power Mode or on a low battery, if that setting is on.
    private func updatePowerState() {
        let shouldPause = preferences.pausesOnLowBattery && powerMonitor.isLowOnPower
        guard shouldPause != isPausedForPower else { return }
        isPausedForPower = shouldPause
        for screenOverlay in screenOverlays {
            screenOverlay.setPausedForPower(shouldPause)
        }
        if !shouldPause {
            refreshTrackedWindows()
        }
    }

    private func updateAccessibilitySettings() {
        reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        applyWeatherEffect()
        applySkyTint()
    }

    /// Builds fresh overlays when screens are plugged in, unplugged, or rearranged.
    private func rebuildOverlays() {
        for screenOverlay in screenOverlays {
            screenOverlay.close()
        }
        screenOverlays = NSScreen.screens.map { ScreenOverlay(screen: $0) }
        applyPreferences()
        for screenOverlay in screenOverlays {
            screenOverlay.setPaused(isPaused)
            screenOverlay.setPausedForPower(isPausedForPower)
        }
    }

    // MARK: - Settings

    /// Sends the current settings to every screen and redraws the weather with them.
    private func applyPreferences() {
        for screenOverlay in screenOverlays {
            screenOverlay.pilesSnowOnWindows = preferences.pilesSnowOnWindows
            screenOverlay.showsDockEffects = preferences.showsDockEffects
            screenOverlay.pausesInFullScreen = preferences.pausesInFullScreen
            screenOverlay.cursorInteracts = preferences.cursorInteracts
        }
        updatePowerState()
        applyWeatherEffect()
        applySkyTint()
        refreshTrackedWindows()
    }

    /// Turns "open at login" on or off with the system.
    private func updateLoginItem() {
        do {
            if launchesAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Couldn't change the login item: \(error.localizedDescription, privacy: .public)")
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// Applies settings and accessibility options to what's about to be shown.
    private func adjustedForSettings(_ effect: WeatherEffect, isLive: Bool) -> WeatherEffect {
        var adjusted = effect
        // Reduce Motion means fewer moving things and no flashing.
        let amount = CGFloat(preferences.effectAmount) * (reducesMotion ? 0.5 : 1)
        adjusted.snowIntensity = min(effect.snowIntensity * amount, 1.5)
        adjusted.rainIntensity = min(effect.rainIntensity * amount, 1.5)
        adjusted.ambientLayers = effect.ambientLayers.map { layer in
            var scaled = layer
            scaled.amount = min(layer.amount * amount, 1)
            return scaled
        }
        adjusted.customLayers = effect.customLayers.map { layer in
            var scaled = layer
            scaled.amount = min(layer.amount * amount, 1.5)
            return scaled
        }
        if !preferences.showsLightningFlashes || reducesMotion {
            adjusted.hasLightning = false
        }
        if isLive, !preferences.showsSeasonalExtras {
            adjusted.ambientLayers = []
        }
        // Reduce Transparency means no see-through fog over the desktop.
        if reducesTransparency {
            adjusted.fogAmount = 0
        }
        return adjusted
    }

    // MARK: - Menu display

    /// One-line weather summary for the menu.
    var weatherSummary: String {
        switch weatherStatus {
        case .locating:
            String(localized: "Finding your location…")
        case .loading:
            String(localized: "Loading weather…")
        case .current(let report):
            "\(report.condition.displayName), \(Self.formattedTemperature(report.temperatureCelsius))"
        case .locationDenied:
            String(localized: "Location is off. Showing snow.")
        case .unavailable:
            String(localized: "Weather unavailable. Showing snow.")
        }
    }

    /// SF Symbol for the menu bar: what's showing, or a snowflake until live weather loads.
    var menuBarSymbolName: String {
        switch weatherSource {
        case .preview(let preview):
            return preview.symbolName
        case .custom:
            if let describedWeather {
                return describedWeather.effect.symbolName(isNight: describedWeather.skyTint.strength > 0.5)
            }
        case .live:
            break
        }
        if case .current(let report) = weatherStatus {
            return report.condition.symbolName(isDay: report.isDay)
        }
        return "snowflake"
    }

    // MARK: - Described weather

    /// Whether Apple Intelligence can interpret descriptions (otherwise keywords are used).
    var isOnDeviceModelAvailable: Bool {
        weatherDescriber.isOnDeviceModelAvailable
    }

    /// Designs a scene from a description (or a surprise, or a change to the current scene) and
    /// switches to it, so nothing else can override it.
    func showDescribedWeather(_ description: String, mode: WeatherDescriber.Mode) async {
        isDescribingWeather = true
        describedWeather = await weatherDescriber.weather(for: description, mode: mode, currentScene: describedWeather)
        isDescribingWeather = false
        weatherSource = .custom
    }

    // MARK: - Permissions

    /// Asks for Accessibility permission so snow fits the Dock exactly. Optional; the Dock is estimated otherwise.
    func requestExactDockFit() {
        dockEstimator.requestExactDockMeasurement()
    }

    /// Shows the Dock permission prompt automatically, but only the first time. Afterward it's in the menu.
    private func offerExactDockFitOnce() {
        let hasOfferedKey = "hasOfferedExactDockFit"
        guard !UserDefaults.standard.bool(forKey: hasOfferedKey), !dockEstimator.canMeasureDockExactly else { return }
        UserDefaults.standard.set(true, forKey: hasOfferedKey)
        requestExactDockFit()
    }

    /// Opens the Location Services pane in System Settings.
    func openLocationSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    private static func formattedTemperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    // MARK: - Live weather

    /// Refreshes weather every 15 minutes (sooner after a failure) and the sky tint every minute.
    private func startWeatherUpdates() {
        weatherTask = Task { [weak self] in
            var nextWeatherRefresh = Date.distantPast
            while !Task.isCancelled {
                guard let self else { return }

                if Date.now >= nextWeatherRefresh {
                    let didRefresh = await self.refreshWeather()
                    nextWeatherRefresh = Date.now.addingTimeInterval(
                        didRefresh ? self.weatherRefreshInterval : self.weatherRetryInterval
                    )
                }
                // Seasonal extras depend on the time of day, so they are re-checked along with the
                // tint. The battery level is re-checked too.
                self.applyWeatherEffect()
                self.applySkyTint()
                self.updatePowerState()

                try? await Task.sleep(for: self.skyTintInterval)
            }
        }
    }

    /// Gets the location (reusing the last one if needed) and fetches current weather. Returns true on success.
    private func refreshWeather() async -> Bool {
        do {
            if lastKnownCoordinate == nil {
                weatherStatus = .locating
            }
            lastKnownCoordinate = try await locationProvider.currentCoordinate()
        } catch LocationProvider.LocationError.denied {
            if lastKnownCoordinate == nil {
                weatherStatus = .locationDenied
                offerExactDockFitOnce()
                return false
            }
        } catch {
            logger.error("Location lookup failed: \(error.localizedDescription, privacy: .public)")
        }

        // Once the location prompt is answered, offer the Dock permission right after it.
        offerExactDockFitOnce()

        guard let coordinate = lastKnownCoordinate else {
            weatherStatus = .unavailable
            return false
        }

        do {
            if latestReport == nil {
                weatherStatus = .loading
            }
            let report = try await weatherClient.fetchCurrentWeather(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            latestReport = report
            weatherStatus = .current(report)
            logger.info("Live weather: \(self.weatherSummary, privacy: .public)")
            applyWeatherEffect()
            if preferences.notifiesFirstSnow {
                await firstSnowNotifier.checkForFirstSnow(
                    report: report,
                    conditionText: weatherSummary,
                    date: .now,
                    latitude: coordinate.latitude
                )
            }
            return true
        } catch {
            logger.error("Weather request failed: \(error.localizedDescription, privacy: .public)")
            if latestReport == nil {
                weatherStatus = .unavailable
            }
            return false
        }
    }

    /// Sends what's selected (a preview, the custom scene, or live weather) to every screen.
    private func applyWeatherEffect() {
        let liveEffect = latestReport.map { WeatherEffect(report: $0, date: .now, latitude: lastKnownCoordinate?.latitude) }
            ?? .fallbackSnow
        let selectedEffect: WeatherEffect = switch weatherSource {
        case .preview(let preview): preview.effect
        case .custom: describedWeather?.effect ?? liveEffect
        case .live: liveEffect
        }
        let effect = adjustedForSettings(selectedEffect, isLive: weatherSource == .live)
        isPrecipitationShowing = effect.snowIntensity > 0 || effect.rainIntensity > 0
        for screenOverlay in screenOverlays {
            screenOverlay.apply(effect)
        }
    }

    /// Darkens the desktop at night once live weather (with sun times) is known,
    /// or as the current preview requires.
    private func applySkyTint() {
        let nightTint = latestReport.map { SkyTint(date: .now, report: $0) } ?? .none
        let liveTint = preferences.darkensDesktopAtNight ? nightTint : .none
        let selectedTint: SkyTint = switch weatherSource {
        case .preview(let preview): preview.skyTint ?? liveTint
        case .custom: describedWeather?.skyTint ?? liveTint
        case .live: liveTint
        }
        // Reduce Transparency means no color washed over the desktop.
        let skyTint = reducesTransparency ? .none : selectedTint
        for screenOverlay in screenOverlays {
            screenOverlay.apply(skyTint)
        }
    }

    // MARK: - Window tracking

    /// Re-reads app window positions about ten times a second so piles follow the windows.
    private func startWindowPolling() {
        windowPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshTrackedWindows()
                let needsFastTracking = self.isPrecipitationShowing || self.screenOverlays.contains { $0.hasPiledSnow }
                try? await Task.sleep(for: needsFastTracking ? self.fastWindowPollingInterval : self.slowWindowPollingInterval)
            }
        }
    }

    private func refreshTrackedWindows() {
        guard !isPaused, !isPausedForPower else { return }

        // The Dock changes rarely, so its estimate is refreshed about once a second.
        if Date.now >= nextDockEstimate {
            let canMeasureDock = dockEstimator.canMeasureDockExactly
            if canMeasureDock != isDockFitExact {
                isDockFitExact = canMeasureDock
            }
            estimatedDockFrame = dockEstimator.estimatedDockFrame()
            nextDockEstimate = Date.now.addingTimeInterval(dockEstimateInterval)
        }

        let trackedWindows = windowTracker.currentWindows()
        // The primary screen (with the menu bar) defines the CoreGraphics coordinate origin.
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0

        for screenOverlay in screenOverlays {
            screenOverlay.updateTrackedWindows(
                trackedWindows,
                dockFrame: estimatedDockFrame,
                primaryScreenHeight: primaryScreenHeight
            )
        }
    }

    // MARK: - Pausing

    /// Pauses or resumes every overlay and catches up on window changes when resuming.
    private func applyPausedState() {
        for screenOverlay in screenOverlays {
            screenOverlay.setPaused(isPaused)
        }
        if !isPaused {
            refreshTrackedWindows()
        }
    }
}
