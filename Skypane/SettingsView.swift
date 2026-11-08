//
//  SettingsView.swift
//  Skypane
//

import SwiftUI

/// The Settings window: how much weather to show, what it can touch, and when it pauses.
struct SettingsView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Form {
            Section("Weather") {
                LabeledContent("Amount") {
                    Slider(value: $appDelegate.preferences.effectAmount, in: 0.3...1.5) {
                        Text("Amount")
                    } minimumValueLabel: {
                        Text("Less")
                    } maximumValueLabel: {
                        Text("More")
                    }
                    .labelsHidden()
                }
                Toggle("Lightning flashes", isOn: $appDelegate.preferences.showsLightningFlashes)
                Toggle("Darken the desktop at night", isOn: $appDelegate.preferences.darkensDesktopAtNight)
                Toggle("Seasonal leaves and fireflies", isOn: $appDelegate.preferences.showsSeasonalExtras)
            }

            Section("Desktop") {
                Toggle("Snow piles on windows", isOn: $appDelegate.preferences.pilesSnowOnWindows)
                Toggle("Snow and rain ripples on the Dock", isOn: $appDelegate.preferences.showsDockEffects)
                Toggle("Cursor brushes snow and wipes fog", isOn: $appDelegate.preferences.cursorInteracts)
            }

            Section("Saving Power") {
                Toggle("Pause behind full-screen apps", isOn: $appDelegate.preferences.pausesInFullScreen)
                Toggle("Pause in Low Power Mode or on low battery", isOn: $appDelegate.preferences.pausesOnLowBattery)
            }

            Section("General") {
                Toggle("Open at login", isOn: $appDelegate.launchesAtLogin)
                Toggle("Notify me of the first snow each winter", isOn: $appDelegate.preferences.notifiesFirstSnow)
            }

            // Explain why some effects look different when accessibility settings are on.
            if appDelegate.reducesMotion || appDelegate.reducesTransparency {
                Section {
                    if appDelegate.reducesMotion {
                        Label("Reduce Motion is on, so there's less movement and no lightning flashes.", systemImage: "figure.walk.motion")
                    }
                    if appDelegate.reducesTransparency {
                        Label("Reduce Transparency is on, so fog and color washes are off.", systemImage: "circle.lefthalf.filled")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
