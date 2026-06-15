//
//  BrightnessController.swift
//  LuxCurve
//
//  Thin Swift wrapper over the display-brightness bridge. Values are linear
//  brightness in 0...1, matching DisplayServices' own scale.
//
//  Scope note: this targets the MAIN built-in display only (per project decision
//  to support the laptop screen first). External-display (DDC) control would be
//  a separate controller behind the same shape — see ARCHITECTURE.md
//  ("Future work — good contributions").
//

import Foundation

final class BrightnessController {

    /// Whether the main display accepts programmatic brightness changes.
    var canControl: Bool {
        LCCanChangeBrightness()
    }

    /// Current linear brightness (0...1), or nil if it could not be read.
    func current() -> Double? {
        var value: Float = 0
        guard LCGetLinearBrightness(&value) else { return nil }
        return Double(value)
    }

    /// Set linear brightness (0...1). Returns whether the write succeeded.
    @discardableResult
    func set(_ value: Double) -> Bool {
        LCSetLinearBrightness(Float(min(1, max(0, value))))
    }
}
