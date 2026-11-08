# Skypane

Skypane puts the weather outside your window onto your Mac's desktop. If it's snowing where you are, snow falls behind your windows and piles up on top of them. If it's raining, rain streaks down and ripples on the Dock. It lives in the menu bar and stays out of your way: clicks go straight through it.

You can also skip the real weather and describe your own scene, like "falling pink dragons and rain" or "campfire under the northern lights", and Skypane builds it.

## What it does

**Live weather**
- Snow, rain, fog, and thunderstorms based on the current conditions where you are, from [Open-Meteo](https://open-meteo.com)
- Heavier rain and snow when it's coming down harder, and wind that pushes everything sideways
- The desktop darkens a little at night, following your local sunrise and sunset
- Autumn leaves on dry fall days, and fireflies on warm summer nights
- A notification the first time it snows each winter

**On your desktop**
- Snow piles up on the top edges of your windows and slides off when you move or resize them
- Snow collects on the Dock, and rain makes small ripples on it
- Lightning lights up the edges of the screen
- Flick the cursor through a snow pile to knock it off, or move it through fog to wipe a patch clear

**Custom scenes**

Open the menu and choose **Describe Weather…**, then type whatever you'd like to see. Anything goes: snow and rain at the same time, colored snow, animals, food, confetti, stars. Things Skypane draws on its own (snow, rain, fog, lightning, leaves, petals, confetti, fireflies, embers, bubbles, stars, dust, auroras, shooting stars) use those effects. Everything else turns into emoji.

A few things to try:
- `falling pink dragons and rain`
- `orange snow with purple leaves`
- `floating hearts on a pink sky`
- `raining tacos at night`

Once a scene is showing, type a change like `more wind`, `make the dragons blue`, or `remove the rain` and click **Change Current Scene**. **Surprise Me** lets Skypane come up with one on its own.

Custom scenes use Apple Intelligence when it's turned on. It runs on your Mac, so what you type never leaves it. Without Apple Intelligence, Skypane still understands common words like snow, rain, leaves, stars, and hearts.

## Installing

1. Download the latest `Skypane.dmg` from [Releases](https://github.com/HussainRaza28/Skypane/releases).
2. Open it and drag **Skypane** into **Applications**.
3. Open Skypane. macOS will say it can't verify the app, because it isn't signed with a paid Apple Developer certificate. Click **Done**.
4. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the message about Skypane.

You only have to do this once. After that it opens like any other app.

Skypane needs **macOS 27.2 or later**.

## Permissions

- **Location** is used to look up the weather where you are. Your approximate coordinates go to Open-Meteo for the forecast and nowhere else. If you say no, Skypane shows gentle snow instead.
- **Accessibility** is optional. Skypane asks for it once so snow fits your Dock exactly. Without it, Skypane estimates the Dock's size, which can come up a little short if you have minimized windows in it. You can turn it on later from the menu with **Fit Snow to Dock…**.
- **Notifications** are only requested the first time it snows, for the first-snow alert.

Skypane never needs Screen Recording. It only reads where windows are, not what's in them.

## Settings

Open **Settings…** from the menu (or press ⌘,) to:
- Show more or less weather
- Turn lightning, night darkening, and seasonal effects on or off
- Choose whether snow piles on windows, collects on the Dock, and reacts to the cursor
- Pause behind full-screen apps, and in Low Power Mode or when the battery is low
- Open Skypane at login

Skypane also follows **Reduce Motion** (less movement, no lightning flashes) and **Reduce Transparency** (no fog or color washes) from your accessibility settings.

## Building from source

You'll need Xcode 27 or later.

1. Clone this repo and open `Skypane.xcodeproj`.
2. Choose the **Skypane** scheme and **My Mac**, then press ⌘R.

Builds from Xcode open without the "can't verify" warning, since they're made on your own Mac. When running from Xcode, the menu also has **Preview Weather** for trying each kind of weather without waiting for it outside.

To make a `.dmg` yourself, run:

```bash
scripts/make-dmg.sh
```

It ends up in `dist/`. If you do have a Developer ID certificate, the top of the script explains how to sign and notarize it so other Macs open it without a warning.

## Built with

Swift, SwiftUI, AppKit, and SpriteKit, with Apple's Foundation Models framework for custom scenes. There are no third-party packages. Weather data comes from [Open-Meteo](https://open-meteo.com), which is free and doesn't need an API key.
