//
//  Circadian.swift
//  LuxCurve
//
//  A gentle time-of-day brightness scale applied on top of the lux curve, so the
//  screen eases down in the late evening and overnight regardless of room light.
//  Pure and stateless; the daemon multiplies the curve's target by this factor.
//
//  Daytime is unscaled (1.0); the factor ramps down to a night floor through the
//  evening and back up around dawn. It never drives the screen to black — the
//  configured minimum-brightness rail still applies after scaling.
//

import Foundation

enum Circadian {

    /// Lowest scale at night. 0.7 = "about 30% dimmer than the curve at the dead
    /// of night," before the brightness rails are re-applied.
    static let nightFloor = 0.7

    private static let dawnEnd = 7.0    // fully day by 07:00
    private static let duskStart = 20.0 // begin easing down at 20:00
    private static let nightStart = 23.0 // night floor reached by 23:00
    private static let dawnStart = 6.0  // begin easing up at 06:00

    /// Brightness scale (nightFloor...1.0) for an hour-of-day in [0, 24).
    static func scale(hour h: Double) -> Double {
        let value: Double
        if h >= dawnEnd && h <= duskStart {
            value = 1.0                                   // daytime plateau
        } else if h >= nightStart || h < dawnStart {
            value = nightFloor                            // night plateau
        } else if h > duskStart {                         // dusk ramp 20:00 -> 23:00
            let t = (h - duskStart) / (nightStart - duskStart)
            value = 1.0 + (nightFloor - 1.0) * t
        } else {                                          // dawn ramp 06:00 -> 07:00
            let t = (h - dawnStart) / (dawnEnd - dawnStart)
            value = nightFloor + (1.0 - nightFloor) * t
        }
        return min(1.0, max(nightFloor, value))
    }

    /// Scale for a given date, using its local hour and minute.
    static func scale(for date: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60.0
        return scale(hour: hour)
    }
}
