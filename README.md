# LuxCurve

LuxCurve is a lightweight, open-source macOS menu-bar app that replaces macOS's
automatic brightness with curves you define. You calibrate it by adjusting the
screen until it is comfortable for the current lighting and saving that point.
Over time, LuxCurve maps your preferred brightness — and, optionally, color
warmth — to each ambient light level.

> Status: **v0.1 — built-in display.** Adapts both brightness and color warmth on
> the built-in display, with a guided calibration window, a Settings window, and
> launch at login. External-display (DDC) support is the main open contribution —
> see [`ARCHITECTURE.md`](ARCHITECTURE.md#future-work).

## Install

No Xcode required — download the ready-to-use app:

**➜ [Download the latest release](https://github.com/nonml/LuxCurve/releases/latest)**
(`LuxCurve.dmg`)

1. Open `LuxCurve.dmg` and drag **LuxCurve** onto the **Applications** shortcut.
   (A `.zip` is also provided if you prefer it.)
2. The build is ad-hoc signed and not notarized, so on first launch macOS
   Gatekeeper blocks a plain double-click. Instead **right-click LuxCurve → Open**,
   then confirm **Open**. If macOS still refuses, go to **System Settings ▸
   Privacy & Security** and click **Open Anyway**. This is a one-time step.
3. Turn off *System Settings → Displays → "Automatically adjust brightness"* so
   that macOS and LuxCurve do not both control the display.

LuxCurve runs as a menu-bar item with no Dock icon — look for the sun glyph. The
first launch opens a short guided calibration.

> Why not notarized / on the App Store? LuxCurve uses private Apple frameworks
> (see below), which rules out the Mac App Store and lets it ship without a paid
> Apple Developer account. See [`DISTRIBUTION.md`](DISTRIBUTION.md) for details.

## Requirements

- Apple Silicon Mac with a built-in display and ambient light sensor
  (for example, any MacBook). Verified on an M3 MacBook Air running macOS 26.4.
- macOS 14.0 or later.

## How it works

- Measures ambient light with the Mac's built-in light sensor (lux).
- Smooths the reading so brief changes in lighting do not cause flicker.
- Maps each light level to a brightness value using a curve you build by calibrating.
- Optionally maps each light level to a **color warmth** as well — warmer in dim
  light, neutral in bright light — using the system Night Shift engine.
- Applies the result to the built-in display.
- Learns from manual brightness adjustments: an adjustment is recorded as a
  calibration point for the current lighting.
- Suggests a sensible starting point for the current lighting (informed by lighting
  ergonomics and circadian research) that you then fine-tune by eye.
- Settings (⌘,) let you tune responsiveness, an overall brightness level, and the
  brightness range; enable a gentle **dim-at-night**; start from a suggested curve;
  manage individual calibration points; and reset.

## Private Apple APIs

LuxCurve reads the light sensor and sets brightness/warmth through undocumented
Apple frameworks (`IOKit`/`IOHIDEventSystem`, `DisplayServices`, and CoreBrightness
for Night Shift). As a result:

- It cannot ship on the Mac App Store; install from a GitHub release or from source.
- A future macOS update could change these APIs. If adaptive brightness stops
  working, run the diagnostic in [`Tooling/sensor-probe/`](Tooling/sensor-probe/) first.
- All private-API use is isolated in one file,
  [`LuxCurve/Bridge/LCBridge.m`](LuxCurve/Bridge/LCBridge.m).

## Build from source

Only needed if you want to build it yourself or contribute. Requires **Xcode 16
or later**.

```sh
# From the repo root
open LuxCurve.xcodeproj      # then press ▶, or:
xcodebuild -project LuxCurve.xcodeproj -scheme LuxCurve -configuration Debug build
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the design and
[`DISTRIBUTION.md`](DISTRIBUTION.md) for cutting a release.

## Configuration

Your calibration curve and settings are stored in
`~/.config/lux-curve/config.json` (human-readable JSON). Delete the file to start
over, or use **Reset** in Settings.

## License

MIT — see [`LICENSE`](LICENSE).
