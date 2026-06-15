//
//  WarmthController.swift
//  LuxCurve
//
//  Thin Swift wrapper over the color-temperature bridge. Warmth is a 0...1
//  strength (0 = neutral, 1 = warmest), applied through the system Night Shift
//  engine. Like BrightnessController, this targets the main built-in display;
//  external-display warmth (via a gamma transfer table) is future work — see
//  ARCHITECTURE.md.
//

import Foundation

final class WarmthController {

    /// Whether the system color-temperature control is available on this Mac.
    var canControl: Bool {
        LCCanControlWarmth()
    }

    /// Apply a warmth strength (0...1). Returns whether the write succeeded.
    @discardableResult
    func set(_ value: Double) -> Bool {
        LCSetWarmth(Float(min(1, max(0, value))))
    }

    /// Return the display to a neutral color temperature.
    @discardableResult
    func disable() -> Bool {
        LCDisableWarmth()
    }
}
