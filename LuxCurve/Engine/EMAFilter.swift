//
//  EMAFilter.swift
//  LuxCurve
//
//  Exponential Moving Average. The ambient sensor is noisy and reacts to passing
//  shadows (a hand, someone walking by). Smoothing prevents the screen from
//  flickering. Alpha ~0.15 means each new reading nudges the average ~15%.
//
//  IMPORTANT: feed this log-lux, not raw lux (see DaemonManager) — averaging in
//  the linear domain lets a single bright spike dominate.
//

import Foundation

struct EMAFilter {
    let alpha: Double
    private(set) var value: Double?

    init(alpha: Double = 0.15) {
        self.alpha = min(1, max(0, alpha))
    }

    /// Fold a new sample into the average and return the updated value.
    @discardableResult
    mutating func update(_ sample: Double) -> Double {
        if let current = value {
            let next = alpha * sample + (1 - alpha) * current
            value = next
            return next
        } else {
            value = sample   // first reading seeds the average
            return sample
        }
    }

    mutating func reset() {
        value = nil
    }
}
