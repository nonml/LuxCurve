//
//  AppConfig.swift
//  LuxCurve
//
//  The full persisted state, serialized to ~/.config/lux-curve/config.json.
//
//  Decoding is tolerant of missing keys (each field falls back to its default)
//  so that a config written by an older version still loads cleanly instead of
//  being treated as corrupt. Bump `version` when the schema changes.
//

import Foundation

struct AppConfig: Codable, Equatable {
    /// Schema version, so future migrations can detect old files.
    var version: Int = 4

    /// Master on/off for adaptive brightness.
    var enabled: Bool = true

    /// EMA smoothing factor for log-lux. Lower = smoother/slower to react.
    var emaAlpha: Double = 0.15

    /// Safety rails so the curve can never drive the screen fully dark/blinding.
    var minBrightness: Double = 0.05
    var maxBrightness: Double = 1.0

    /// The user's personal brightness curve (lux → brightness).
    var curve: CalibrationCurve = CalibrationCurve()

    /// Adaptive warmth (color temperature) on/off. Off by default; turned on once
    /// the user calibrates a warmth point.
    var warmthEnabled: Bool = false

    /// The user's warmth curve (lux → warmth strength). Reuses `CalibrationNode`,
    /// where the node's `brightness` field stores the warmth strength (0...1,
    /// higher = warmer). Warmth is applied via the system Night Shift engine.
    var warmthCurve: CalibrationCurve = CalibrationCurve()

    /// A time-of-day dimming on top of the curve (eases the screen down at night).
    var circadianEnabled: Bool = false

    /// Overall brightness multiplier applied on top of the curve (0.5...1.5),
    /// for a quick "everything dimmer/brighter" without re-calibrating.
    var brightnessScale: Double = 1.0

    /// Whether a settled manual brightness adjustment is collected as a learned
    /// calibration point.
    var learnFromAdjustments: Bool = true

    static let `default` = AppConfig()

    init() {}

    enum CodingKeys: String, CodingKey {
        case version, enabled, emaAlpha, minBrightness, maxBrightness, curve
        case warmthEnabled, warmthCurve, circadianEnabled, brightnessScale
        case learnFromAdjustments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        version        = (try? c.decode(Int.self,    forKey: .version))        ?? d.version
        enabled        = (try? c.decode(Bool.self,   forKey: .enabled))        ?? d.enabled
        emaAlpha       = (try? c.decode(Double.self, forKey: .emaAlpha))       ?? d.emaAlpha
        minBrightness  = (try? c.decode(Double.self, forKey: .minBrightness))  ?? d.minBrightness
        maxBrightness  = (try? c.decode(Double.self, forKey: .maxBrightness))  ?? d.maxBrightness
        curve          = (try? c.decode(CalibrationCurve.self, forKey: .curve)) ?? d.curve
        warmthEnabled  = (try? c.decode(Bool.self,   forKey: .warmthEnabled))  ?? d.warmthEnabled
        warmthCurve    = (try? c.decode(CalibrationCurve.self, forKey: .warmthCurve)) ?? d.warmthCurve
        circadianEnabled = (try? c.decode(Bool.self,   forKey: .circadianEnabled)) ?? d.circadianEnabled
        brightnessScale  = (try? c.decode(Double.self, forKey: .brightnessScale))  ?? d.brightnessScale
        learnFromAdjustments = (try? c.decode(Bool.self, forKey: .learnFromAdjustments)) ?? d.learnFromAdjustments
    }
}
