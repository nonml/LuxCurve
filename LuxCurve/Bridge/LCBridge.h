//
//  LCBridge.h
//  LuxCurve
//
//  Clean C surface over the private macOS APIs LuxCurve depends on.
//  ALL contact with private/undocumented Apple APIs is isolated in this one
//  translation unit so the rest of the app stays in safe, public Swift.
//
//  Verified working on Apple Silicon (M3) / macOS 26.4 via Tooling/sensor-probe.
//  If a future macOS update breaks adaptive brightness, re-run that probe first.
//

#ifndef LCBRIDGE_H
#define LCBRIDGE_H

#include <stdbool.h>
#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Reads the built-in ambient light sensor.
/// Returns lux (>= 0) on success and writes `true` to *ok.
/// On failure returns 0 and writes `false` to *ok (e.g. a Mac with no sensor).
double LCReadAmbientLux(bool *ok);

/// True if the main display's brightness can be changed programmatically.
bool LCCanChangeBrightness(void);

/// Reads the main display's linear brightness (0.0...1.0).
/// Returns true on success and writes the value to *outValue.
bool LCGetLinearBrightness(float *outValue);

/// Sets the main display's linear brightness. `value` is clamped to 0.0...1.0.
/// Returns true on success.
bool LCSetLinearBrightness(float value);

/// True if the system color-temperature control (Night Shift) is available.
bool LCCanControlWarmth(void);

/// Sets adaptive warmth as a 0.0...1.0 strength (0 = neutral, 1 = warmest) via
/// the system Night Shift engine. A strength of 0 returns the display to neutral.
/// Returns true on success.
bool LCSetWarmth(float strength);

/// Returns the display to a neutral color temperature (disables Night Shift).
/// Returns true on success.
bool LCDisableWarmth(void);

#ifdef __cplusplus
}
#endif

#endif /* LCBRIDGE_H */
