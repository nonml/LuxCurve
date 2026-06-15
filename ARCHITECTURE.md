# LuxCurve Architecture

This document describes how the components fit together so that a new contributor
can extend the app without re-deriving the design. It reflects the current state
of the repository.

## Layered design (bottom to top)

```
┌───────────────────────────────────────────────────────────────┐
│  UI (SwiftUI)                                                 │
│   MenuBarView · CalibrationWizardView · SettingsView          │
├───────────────────────────────────────────────────────────────┤
│  App orchestration                                            │
│   LuxCurveApp (@main) · AppModel (config + actions)           │
├───────────────────────────────────────────────────────────────┤
│  Engine / runtime loop                                        │
│   DaemonManager (tick loop, EMA, nudges, warmth)              │
│   CurveEngine (lux→brightness, lux→warmth) · EMAFilter        │
├───────────────────────────────────────────────────────────────┤
│  Data                                                         │
│   AppConfig · CalibrationCurve · CalibrationNode              │
│   ConfigManager (~/.config/lux-curve/config.json)             │
├───────────────────────────────────────────────────────────────┤
│  Hardware wrappers (Swift)                                    │
│   ALSSensor · BrightnessController · WarmthController         │
├───────────────────────────────────────────────────────────────┤
│  Private-API bridge                                           │
│   LCBridge.m  +  LuxCurve-Bridging-Header.h                   │
│   IOKit (sensor) · DisplayServices · CoreBrightness           │
└───────────────────────────────────────────────────────────────┘
```

**Design rule:** every private or undocumented Apple call lives in
`LuxCurve/Bridge/LCBridge.m` and is exposed to Swift as a small C API — the sensor
and brightness functions (`LCReadAmbientLux`, `LCGetLinearBrightness`,
`LCSetLinearBrightness`, `LCCanChangeBrightness`) and the warmth functions
(`LCCanControlWarmth`, `LCSetWarmth`, `LCDisableWarmth`). No code above the bridge
references a private symbol. If macOS changes these APIs, this is the only file to
update;
[`Tooling/sensor-probe/`](Tooling/sensor-probe/) is a standalone harness for
re-verifying them on hardware.

## The runtime loop (`DaemonManager`)

Driven by a 1.5 s main-runloop `Timer` (the manager is `@MainActor`). Each tick:

1. `ALSSensor.currentLux()` returns the raw lux value.
2. The reading is EMA-smoothed in **log-lux** space, which matches perceived
   brightness and limits the influence of brief spikes.
3. `CurveEngine.brightness(forLux:nodes:)` returns the target brightness, or `nil`
   when no calibration exists yet (in which case the display is left unchanged).
4. The target is clamped to the `[minBrightness, maxBrightness]` safety rails.
5. `BrightnessController` applies the value only when it moves past a small
   deadband, easing the change over several frames rather than setting it at once.
6. **Manual-nudge detection:** if the display's actual brightness diverges from
   the value LuxCurve last wrote (beyond a threshold), the user has adjusted
   brightness manually. LuxCurve stops overriding and reports the adjustment.
7. **Warmth:** the tick also reconciles color temperature from the warmth curve,
   independently of any brightness override (see *Adaptive warmth* below).

On wake from sleep and on display reconfiguration, the daemon re-applies the curve
and re-seeds the EMA, so a large change in lighting after the lid opens is applied
promptly. When the built-in display is unreachable (clamshell or external-only
configurations), the daemon pauses.

## Learning from a manual adjustment

A settled manual brightness adjustment is collected as a calibration point for the
current lighting (unless "Learn from manual adjustments" is turned off in Settings):

- **Debounce** — LuxCurve waits for the value to settle (about 3 s) and records it
  once, *after* the user stops adjusting, rather than recording each intermediate
  value while a key is held.
- **Normalization** — the applied brightness includes the overall scale and any
  circadian dimming, so those are divided out before storing; the curve stays a
  clean baseline lux→brightness mapping that, re-scaled, reproduces the user's choice.
- **Provenance** — points are tagged `.explicit` (calibration window) or `.learned`
  (a settled adjustment). A learned point is collected as its *own* data point
  alongside nearby explicit ones — it updates a nearby learned point but never
  overwrites a deliberate `.explicit` calibration. Individual points are viewable
  and deletable in the calibration-points window.

## The math (`CurveEngine`)

- Pure and stateless (an `enum` with static methods), which keeps it simple to
  unit-test.
- A single generic core, `value(forLux:points:)`, performs **monotone cubic
  interpolation** (PCHIP / Fritsch–Carlson) in log-lux between calibration points,
  producing a smooth curve with no overshoot between points and a non-decreasing
  result. `brightness(forLux:nodes:)` and `warmth(forLux:nodes:)` are thin wrappers
  over it.
- Guarantees **monotonicity**: brightness never decreases as lux increases.
- Below the lowest and above the highest calibrated lux, it holds the endpoint value.

## Adaptive warmth (color temperature)

A second `lux → warmth` curve drives the display's color temperature: warmer in
dim or evening light, neutral in bright light. It reuses the same `CurveEngine`,
the same `CalibrationNode`/`CalibrationCurve` storage (the node's `brightness`
field holds the warmth strength, 0...1), and the same calibration UI with an added
slider.

- **Direction.** Warmth must be monotone *non-increasing* in lux. `CurveEngine`
  guarantees the opposite direction, so `warmth(forLux:nodes:)` interpolates
  coolness (`1 − warmth`), which is non-decreasing, and inverts the result. The
  warmth guarantee then comes for free, including the clamp when calibrated points
  are out of order.
- **Application.** `WarmthController` applies the value through the system Night
  Shift engine (`CBBlueLightClient` in the private CoreBrightness framework, loaded
  at runtime by `LCBridge.m`). The daemon reconciles warmth each tick and only
  writes past a small deadband.
- **Safety.** The daemon returns the display to neutral when warmth is turned off,
  when the master switch is off, and on app termination — but only if it was the
  one that changed the color temperature, so it never disturbs a user's own Night
  Shift schedule when warmth was never active.
- **Opt-in.** Warmth is off until the user calibrates a warmth point, which turns
  it on.

## Calibration guidance (`CalibrationGuidance`)

So the user adjusts from a sensible baseline rather than a blank slider,
`CalibrationGuidance` is a pure type that, for a given lux, returns a human label
for the lighting ("Office / bright indoor"), a short note, and suggested
brightness/warmth values. The suggestions are interpolated through baseline nodes
by the same `CurveEngine`, so they share the curves' monotonicity. The calibration
window shows the label and a "Use suggested" button; Settings offers "Start from a
suggested curve" to seed both curves at once.

The file documents what is research-backed versus a rule of thumb: room-light
targets (EN 12464-1 / ISO 8995: ~500 lux for reading), the screen-to-room matching
principle (ISO 9241-303), and warmer-at-night (circadian/melatonin research) are
grounded; the brightness *percentages* are a deliberately modest rule of thumb,
because comfortable luminance is measured in nits and depends on the display's
maximum, which the app does not read. The numbers are starting points to adjust by
eye, not health figures.

## Brightness shaping (on top of the curve)

After the curve produces a target, the daemon applies two optional adjustments
before the safety rails:

- **Overall brightness scale** (`brightnessScale`, 0.5...1.5) — a single
  multiplier for "everything dimmer/brighter" without re-calibrating.
- **Circadian dimming** (`Circadian`, opt-in) — a time-of-day multiplier (1.0 in
  daytime, easing to a night floor of 0.7 overnight, with dusk/dawn ramps). Pure
  and stateless; no new private API.

Both are multiplied into the target, then clamped to `[minBrightness,
maxBrightness]`, so the rails always have the final say.

## Data and persistence

- `CalibrationNode(lux, brightness)` — a single calibration point; `Codable` and
  tolerant of older JSON that lacks an `id`.
- `CalibrationCurve` — sorted nodes; `upsert` replaces a point captured at nearly
  the same lux (within a relative tolerance) rather than duplicating it.
- `AppConfig` — versioned; holds `enabled`, `emaAlpha`, the safety rails, and the curve.
- `ConfigManager` — writes `~/.config/lux-curve/config.json` atomically and backs
  up a file that fails to parse rather than discarding the user's calibration.

> First-run and onboarding flags are stored in `UserDefaults`, not in
> `config.json`, so that adding a UI flag never requires a `Codable` migration of
> the user's curve.

## App shell

- `LuxCurveApp` (`@main`) declares a `MenuBarExtra` (`.window` style), `Window`s for
  the calibration UI and the calibration-points list, and a `Settings` scene.
  `LSUIElement = YES` (a build setting) keeps the app out of the Dock.
- The menu-bar popover is intentionally minimal: live readings, a single master
  on/off, and entry points to the calibration window and Settings. All other
  configuration — adaptive warmth, open-at-login, responsiveness, brightness range,
  suggested curve, and resets — lives in the **Settings window** (`SettingsView`, ⌘,).
- The menu-bar glyph reflects the enabled/disabled state.
- On first run, the app opens the guided calibration flow and explains turning off
  the macOS "Automatically adjust brightness" setting.
- Launch at login uses `SMAppService` (ServiceManagement), toggled from Settings.
- `AppModel` is the single source of truth for configuration and actions; views
  observe it and `DaemonManager` (for live readings) via `@EnvironmentObject`.

## Project mechanics

- **Synchronized file group** (Xcode 16+, `objectVersion = 77`): every file under
  `LuxCurve/` is automatically a target member. Add files by creating them in the
  folder; no `.pbxproj` editing is required.
- Swift **language mode 6** (strict concurrency). The runtime types that touch the
  UI and hardware are annotated `@MainActor`.
- Tests live in the `LuxCurveTests` target (hosted, `@testable import`) and cover
  `CurveEngine` and `EMAFilter`. Run them with:
  ```sh
  xcodebuild -project LuxCurve.xcodeproj -scheme LuxCurve -destination 'platform=macOS' test
  ```
- The private frameworks are wired through build settings: `FRAMEWORK_SEARCH_PATHS`
  includes `/System/Library/PrivateFrameworks`, and `OTHER_LDFLAGS` links `IOKit`,
  `CoreGraphics`, and `DisplayServices`. CoreBrightness (Night Shift) is loaded at
  runtime with `dlopen` instead of linked, so the app degrades gracefully if it is
  ever unavailable. The app sandbox is disabled, which the private APIs and
  `~/.config` access require.

## Future work

The following items are out of scope for the current release (built-in display
only) and are suitable for contribution. They are listed roughly in order of
expected benefit to viewing comfort.

- **Warmth on external displays.** Adaptive warmth currently uses the system Night
  Shift engine, which targets the built-in display. Extending it to external
  monitors means driving a **gamma transfer table** (`CGSetDisplayTransferByTable`,
  public CoreGraphics) to reduce the blue channel directly — more control and
  multi-display reach, but the app must compute the table and restore it on quit
  and sleep.
- **External-display brightness (DDC/CI).** A second `BrightnessController`
  implementation behind the existing interface, shelling out to
  [`m1ddc`](https://github.com/waydabber/m1ddc) or `ddcctl`, with per-display
  curves so each monitor has its own mapping. `BrightnessController` and
  `CurveEngine` are designed to accommodate this without a rewrite.

Two related controls were considered and are intentionally out of scope: *contrast*
has no continuous panel-level API (only the binary "Increase contrast" accessibility
setting), and *grayscale* is an accessibility filter unrelated to ambient-light
comfort. Either could be a simple toggle, but neither warrants a calibrated curve.

When extending the app, please preserve the guardrails: all private-API calls
remain in `LCBridge.m`; `CurveEngine` remains pure and stateless so it stays
testable; and configuration writes remain atomic and never discard the user's
calibration on a parse error.
