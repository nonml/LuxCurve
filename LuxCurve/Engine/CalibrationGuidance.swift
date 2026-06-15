//
//  CalibrationGuidance.swift
//  LuxCurve
//
//  Turns "this feels right" into "this feels right, starting from somewhere
//  sensible." Provides a human label for the current lighting, a short
//  research-grounded note, suggested starting values, and a baseline curve the
//  user can adopt and then fine-tune.
//
//  What is research-backed vs. a rule of thumb (be honest about the difference):
//
//   * Room light targets ARE backed by standards. EN 12464-1 / ISO 8995 set
//     ~500 lux for reading and computer work, ~300 lux for lighter tasks. The
//     band labels and the "comfortable reading light is ~300–500 lux" note come
//     from there.
//   * The "match the screen to the room" principle and avoiding a bright screen
//     in a dark room are ergonomic guidance (ISO 9241-303; American Optometric
//     Association). Comfortable screen luminance is roughly 120–150 nits in an
//     office, 80–100 in a dim room, 50–80 in near-dark.
//   * Warmer light in the evening is backed by circadian research: warm (~<=3000 K)
//     light suppresses melatonin far less than cool (~6200 K) light.
//
//   * The brightness PERCENTAGES below are a rule of thumb, NOT a health figure.
//     Comfortable brightness is a luminance (nits) that depends on the specific
//     display's maximum, which we do not read, so a percentage cannot be a
//     standard. They are derived from the nit targets above assuming a typical
//     laptop panel, kept deliberately modest, and meant to be adjusted by eye.
//

import Foundation

enum CalibrationGuidance {

    /// A lighting band: everything up to `maxLux`, with a label, a short note, and
    /// suggested starting values. `warmth` is 0...1 (1 = warmest).
    struct Band {
        let maxLux: Double
        let label: String
        let note: String
        let representativeLux: Double
        let brightness: Double
        let warmth: Double
    }

    private static let dimNote = "In a dark room, a dimmer and warmer screen is easier on the eyes — and warm light in the evening helps sleep."
    private static let indoorNote = "Comfortable reading light is about 300–500 lux. Aim to match the screen to the room rather than outshining it."
    private static let brightNote = "In bright light, raise brightness to match your surroundings and reduce glare."

    /// Ordered ascending by `maxLux`; the last band is open-ended.
    static let bands: [Band] = [
        Band(maxLux: 10,        label: "Night / very dim",       note: dimNote,    representativeLux: 4,      brightness: 0.12, warmth: 0.85),
        Band(maxLux: 50,        label: "Dim room",               note: dimNote,    representativeLux: 25,     brightness: 0.20, warmth: 0.65),
        Band(maxLux: 200,       label: "Indoor / living room",   note: indoorNote, representativeLux: 110,    brightness: 0.30, warmth: 0.48),
        Band(maxLux: 500,       label: "Office / bright indoor", note: indoorNote, representativeLux: 320,     brightness: 0.45, warmth: 0.32),
        Band(maxLux: 2_000,     label: "Very bright indoor",     note: brightNote, representativeLux: 1_100,   brightness: 0.62, warmth: 0.18),
        Band(maxLux: 10_000,    label: "Daylight (indirect)",    note: brightNote, representativeLux: 5_000,   brightness: 0.85, warmth: 0.08),
        Band(maxLux: .infinity, label: "Direct daylight",        note: brightNote, representativeLux: 20_000,  brightness: 1.00, warmth: 0.0),
    ]

    /// The band a lux reading falls into.
    static func band(forLux lux: Double) -> Band {
        bands.first { lux <= $0.maxLux } ?? bands[bands.count - 1]
    }

    /// A short human description of the current lighting, e.g. "Office / bright indoor".
    static func label(forLux lux: Double) -> String {
        band(forLux: lux).label
    }

    /// A short research-grounded note appropriate to the current lighting.
    static func note(forLux lux: Double) -> String {
        band(forLux: lux).note
    }

    /// Smooth suggested values at any lux, interpolated through the baseline nodes
    /// by the same engine the real curves use (so suggestions are monotonic too).
    static func suggestedBrightness(forLux lux: Double) -> Double {
        CurveEngine.brightness(forLux: lux, nodes: suggestedBrightnessNodes()) ?? band(forLux: lux).brightness
    }

    static func suggestedWarmth(forLux lux: Double) -> Double {
        CurveEngine.warmth(forLux: lux, nodes: suggestedWarmthNodes()) ?? band(forLux: lux).warmth
    }

    /// A baseline brightness curve — one point per band at a representative lux.
    static func suggestedBrightnessNodes() -> [CalibrationNode] {
        bands.map { CalibrationNode(lux: $0.representativeLux, brightness: $0.brightness) }
    }

    /// A baseline warmth curve (node `brightness` field holds the warmth strength).
    static func suggestedWarmthNodes() -> [CalibrationNode] {
        bands.map { CalibrationNode(lux: $0.representativeLux, brightness: $0.warmth) }
    }
}
