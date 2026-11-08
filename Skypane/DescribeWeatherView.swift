//
//  DescribeWeatherView.swift
//  Skypane
//

import SwiftUI

/// A small window where you describe any scene you'd like, such as "falling pink dragons and rain".
/// Return creates a new scene; changing the current scene and surprises have their own buttons.
struct DescribeWeatherView: View {
    static let windowID = "describe-weather"

    /// Ideas shown as placeholder text, so people can see what's possible.
    private static let examplePrompts = [
        "falling pink dragons and rain",
        "cozy snowy evening with fireflies",
        "floating hearts on a pink sky",
        "campfire under the northern lights",
        "raining pizza and confetti",
        "orange snow with purple leaves",
        "butterflies in a spring breeze",
        "spooky night with ghosts and fog",
    ]

    @ObservedObject var appDelegate: AppDelegate
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var sceneDescription = ""
    @State private var examplePrompt = Self.examplePrompts.randomElement() ?? ""

    private var trimmedDescription: String {
        sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedDescription.isEmpty && !appDelegate.isDescribingWeather
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe any scene")
                .font(.headline)
            Text("Mix anything: weather, animals, food, objects, colors. Name a color for any part, like “orange snow” or “pink dragons”.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Try: \(examplePrompt)", text: $sceneDescription)
                .textFieldStyle(.roundedBorder)
                .onSubmit { describe(.newScene) }
                .disabled(appDelegate.isDescribingWeather)

            if let describedWeather = appDelegate.describedWeather {
                Text("Current scene: \(describedWeather.title) — \(describedWeather.summary)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Without Apple Intelligence, common words still work.
            if !appDelegate.isOnDeviceModelAvailable {
                Text("Apple Intelligence is off, so Skypane only recognizes common words like snow, rain, leaves, stars, hearts, and balloons.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Surprise Me") {
                    describe(.surprise)
                }
                .disabled(appDelegate.isDescribingWeather)

                if appDelegate.isDescribingWeather {
                    ProgressView()
                        .controlSize(.small)
                    Text("Designing…")
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button("Cancel") {
                    dismissWindow(id: Self.windowID)
                }
                .keyboardShortcut(.cancelAction)

                if appDelegate.describedWeather != nil {
                    Button("Change Current Scene") {
                        describe(.changeCurrentScene)
                    }
                    .disabled(!canSubmit)
                }

                Button("Create Scene") {
                    describe(.newScene)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            examplePrompt = Self.examplePrompts.randomElement() ?? examplePrompt
        }
    }

    private func describe(_ mode: WeatherDescriber.Mode) {
        guard !appDelegate.isDescribingWeather else { return }
        let description = trimmedDescription
        guard mode == .surprise || !description.isEmpty else { return }

        Task {
            await appDelegate.showDescribedWeather(description, mode: mode)
            sceneDescription = ""
            dismissWindow(id: Self.windowID)
        }
    }
}
