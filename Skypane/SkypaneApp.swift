//
//  SkypaneApp.swift
//  Skypane
//
//  Created by Hussain Raza on 11/7/26.
//

import SwiftUI

@main
struct SkypaneApp: App {
    // Owns the overlay windows, live weather, and the paused state.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar icon with the app's controls; there is no main window.
        MenuBarExtra {
            WeatherMenu(appDelegate: appDelegate)
        } label: {
            MenuBarIcon(appDelegate: appDelegate)
        }

        // Opened from the menu to type a description of the weather to show.
        Window("Describe Weather", id: DescribeWeatherView.windowID) {
            DescribeWeatherView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        // Floats above other apps' windows. A menu bar app isn't always allowed to come to the
        // front when it asks, so without this the window can open hidden behind other windows.
        .windowLevel(.floating)

        // Settings, opened from the menu. Floats for the same reason as the Describe window.
        Window("Skypane Settings", id: settingsWindowID) {
            SettingsView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .windowLevel(.floating)
    }
}

/// The Settings window's identifier, used to open it from the menu.
private let settingsWindowID = "settings"

/// The menu bar icon, which follows the current weather.
private struct MenuBarIcon: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Image(systemName: appDelegate.menuBarSymbolName)
            .accessibilityLabel("Skypane")
    }
}

/// Contents of the menu bar dropdown.
private struct WeatherMenu: View {
    @ObservedObject var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Current conditions, shown as a non-interactive line.
        Text(appDelegate.weatherSummary)

        Divider()

        // One choice for what's showing, with a checkmark on the active one.
        Picker("Show", selection: $appDelegate.weatherSource) {
            Text("Live Weather").tag(WeatherSource.live)
            if let describedWeather = appDelegate.describedWeather {
                Text("Custom: \(describedWeather.title)").tag(WeatherSource.custom)
            }
        }
        .pickerStyle(.inline)

        // What the custom scene contains, so it's clear what the AI made.
        if appDelegate.weatherSource == .custom, let describedWeather = appDelegate.describedWeather {
            Text(describedWeather.summary)
        }

        Button("Describe Weather…") {
            openWindow(id: DescribeWeatherView.windowID)
            // Menu bar apps aren't frontmost, so bring the window forward for typing.
            NSApplication.shared.activate()
        }

        #if DEBUG
        Menu("Preview Weather") {
            Picker("Preview Weather", selection: $appDelegate.weatherSource) {
                ForEach(WeatherPreview.allCases) { preview in
                    Text(preview.title).tag(WeatherSource.preview(preview))
                }
            }
            .pickerStyle(.inline)
        }
        #endif

        Divider()

        if appDelegate.weatherStatus == .locationDenied {
            Button("Open Location Settings…") {
                appDelegate.openLocationSettings()
            }
        }

        // Optional: lets snow match the Dock's exact size, including minimized windows.
        if !appDelegate.isDockFitExact {
            Button("Fit Snow to Dock…") {
                appDelegate.requestExactDockFit()
            }
        }

        // Explains an automatic pause, so the weather doesn't seem to have just stopped.
        if appDelegate.isPausedForPower {
            Text("Paused to save power")
        }

        Button(appDelegate.isPaused ? "Resume Weather" : "Pause Weather") {
            appDelegate.isPaused.toggle()
        }

        Button("Settings…") {
            openWindow(id: settingsWindowID)
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Skypane") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
