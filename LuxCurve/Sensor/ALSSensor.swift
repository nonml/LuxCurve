//
//  ALSSensor.swift
//  LuxCurve
//
//  Thin Swift wrapper over the ambient light sensor bridge. Polled by
//  DaemonManager — the underlying read is a fast synchronous IOKit call.
//

import Foundation

final class ALSSensor {

    /// Current ambient light in lux, or nil if no sensor is available
    /// (e.g. a desktop Mac with no built-in display).
    func currentLux() -> Double? {
        var ok = false
        let lux = LCReadAmbientLux(&ok)
        return ok ? lux : nil
    }

    /// Whether this machine exposes a readable ambient light sensor.
    var isAvailable: Bool {
        currentLux() != nil
    }
}
