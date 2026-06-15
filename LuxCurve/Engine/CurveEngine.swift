//
//  CurveEngine.swift
//  LuxCurve
//
//  Maps an ambient lux reading to a target value (screen brightness, or color
//  warmth) using the user's calibration nodes. Two guarantees:
//    1. Monotonic: the interpolated value never reverses direction against lux
//       (we clamp). For brightness this means it never dips as lux rises; warmth
//       is handled as its complement so it never rises as lux rises.
//    2. Interpolated in log-lux space, because human light perception and the
//       sensor's range are both roughly logarithmic — linear-in-lux would make
//       the curve far too sensitive at the bright end.
//
//  Interpolation is monotone cubic (PCHIP, Fritsch–Carlson tangents) in log-lux
//  space: smooth transitions between points without the overshoot a plain cubic
//  would introduce. Because the inputs are clamped non-decreasing (see
//  `monotonic`), the Fritsch–Carlson construction preserves guarantee #1.
//

import Foundation

enum CurveEngine {

    /// A calibrated (lux, value) sample, where `value` is in 0...1.
    typealias Point = (lux: Double, value: Double)

    /// Target linear brightness (0...1) for a given lux, or nil if the user has
    /// not calibrated any points yet (caller should then leave brightness alone).
    static func brightness(forLux lux: Double, nodes: [CalibrationNode]) -> Double? {
        value(forLux: lux, points: nodes.map { (lux: $0.lux, value: $0.brightness) })
    }

    /// Target warmth strength (0...1) for a given lux, or nil if no warmth points
    /// are calibrated. Warmth is monotone *non-increasing* in lux — the display is
    /// warmest in dim light and coolest in bright light. We obtain that guarantee
    /// for free by interpolating coolness (1 − warmth), which is non-decreasing in
    /// lux, through the same engine and inverting the result.
    static func warmth(forLux lux: Double, nodes: [CalibrationNode]) -> Double? {
        let coolness = value(forLux: lux, points: nodes.map { (lux: $0.lux, value: 1 - $0.brightness) })
        return coolness.map { 1 - $0 }
    }

    /// Monotone-cubic interpolation in log-lux of a 0...1 value across calibrated
    /// points, clamped non-decreasing as lux increases. Returns nil if `raw` is
    /// empty, and the single value if only one point is calibrated.
    static func value(forLux lux: Double, points raw: [Point]) -> Double? {
        let points = monotonic(raw.sorted { $0.lux < $1.lux })
        guard let first = points.first else { return nil }
        if points.count == 1 { return first.value }

        let xs = points.map { logLux($0.lux) }
        let ys = points.map { $0.value }
        let x = logLux(lux)

        if x <= xs[0] { return ys[0] }                       // dimmer than calibrated -> floor
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] } // brighter than calibrated -> ceiling

        // Locate the interval [a, b] containing x.
        var b = 1
        while b < xs.count - 1 && x > xs[b] { b += 1 }
        let a = b - 1

        let h = xs[b] - xs[a]
        if h <= 0 { return ys[b] }   // coincident x (shouldn't happen post-upsert)

        let m = monotoneTangents(xs: xs, ys: ys)
        let t = (x - xs[a]) / h
        let t2 = t * t, t3 = t2 * t

        // Cubic Hermite basis.
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        return h00 * ys[a] + h10 * h * m[a] + h01 * ys[b] + h11 * h * m[b]
    }

    /// Fritsch–Carlson tangents for monotone cubic interpolation. With
    /// non-decreasing `ys` all secant slopes are >= 0, so the result is a
    /// monotone (non-decreasing) interpolant with no overshoot.
    private static func monotoneTangents(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        var hs = [Double](repeating: 0, count: n - 1)   // interval widths
        var d  = [Double](repeating: 0, count: n - 1)   // secant slopes
        for k in 0..<(n - 1) {
            hs[k] = xs[k + 1] - xs[k]
            d[k] = hs[k] > 0 ? (ys[k + 1] - ys[k]) / hs[k] : 0
        }

        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for k in 1..<(n - 1) {
            // A flat or sign change forces a zero tangent so flats stay flat.
            if d[k - 1] == 0 || d[k] == 0 || (d[k - 1] > 0) != (d[k] > 0) {
                m[k] = 0
            } else {
                let w1 = 2 * hs[k] + hs[k - 1]
                let w2 = hs[k] + 2 * hs[k - 1]
                m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k])
            }
        }
        return m
    }

    /// Compress lux into a perceptually-sane domain. +1 keeps log(0) well-defined.
    static func logLux(_ lux: Double) -> Double {
        log10(max(0, lux) + 1)
    }

    /// Clamp the value to be non-decreasing with lux, enforcing guarantee #1.
    /// Input must already be sorted ascending by lux.
    static func monotonic(_ sorted: [Point]) -> [Point] {
        var result: [Point] = []
        result.reserveCapacity(sorted.count)
        var runningMax = 0.0
        for var point in sorted {
            if point.value < runningMax {
                point.value = runningMax
            } else {
                runningMax = point.value
            }
            result.append(point)
        }
        return result
    }
}
