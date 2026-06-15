//
//  WarmthCurveTests.swift
//  LuxCurveTests
//
//  Covers CurveEngine.warmth: the no-calibration case, that it passes through
//  calibrated points, endpoint clamping, and the warmth-specific guarantee —
//  warmth is monotone NON-INCREASING in lux (warmest in the dark), including when
//  the calibrated points themselves violate that order.
//

import XCTest
@testable import LuxCurve

final class WarmthCurveTests: XCTestCase {

    /// `brightness` holds the warmth strength for warmth nodes (see AppConfig).
    private func node(_ lux: Double, _ warmth: Double) -> CalibrationNode {
        CalibrationNode(lux: lux, brightness: warmth)
    }

    func testNoNodesReturnsNil() {
        XCTAssertNil(CurveEngine.warmth(forLux: 100, nodes: []))
    }

    func testSingleNodeIsConstant() {
        let nodes = [node(50, 0.7)]
        XCTAssertEqual(CurveEngine.warmth(forLux: 0, nodes: nodes)!, 0.7, accuracy: 1e-9)
        XCTAssertEqual(CurveEngine.warmth(forLux: 5_000, nodes: nodes)!, 0.7, accuracy: 1e-9)
    }

    func testPassesThroughWellOrderedPoints() {
        // Warmth decreasing as lux rises is already valid, so it passes through.
        let nodes = [node(10, 0.9), node(100, 0.6), node(1_000, 0.2)]
        for n in nodes {
            XCTAssertEqual(CurveEngine.warmth(forLux: n.lux, nodes: nodes)!, n.brightness,
                           accuracy: 1e-9, "warmth curve should pass through its own points")
        }
    }

    func testEndpointClamping() {
        let nodes = [node(10, 0.9), node(1_000, 0.2)]
        // Dimmer than calibrated -> warmest endpoint.
        XCTAssertEqual(CurveEngine.warmth(forLux: 0, nodes: nodes)!, 0.9, accuracy: 1e-9)
        XCTAssertEqual(CurveEngine.warmth(forLux: 3, nodes: nodes)!, 0.9, accuracy: 1e-9)
        // Brighter than calibrated -> coolest endpoint.
        XCTAssertEqual(CurveEngine.warmth(forLux: 50_000, nodes: nodes)!, 0.2, accuracy: 1e-9)
    }

    func testMonotonicNonIncreasing() {
        let nodes = [node(5, 0.95), node(80, 0.6), node(400, 0.55), node(8_000, 0.1)]
        var previous = 2.0
        var lux = 0.0
        while lux <= 50_000 {
            let w = CurveEngine.warmth(forLux: lux, nodes: nodes)!
            XCTAssertLessThanOrEqual(w, previous + 1e-9,
                                     "warmth must never rise as lux rises (lux=\(lux))")
            previous = w
            lux += 25
        }
    }

    func testWarmthClampedWhenPointsRiseWithLux() {
        // A point that is warmer at a brighter lux must be clamped down, not honored.
        let nodes = [node(10, 0.3), node(100, 0.8), node(1_000, 0.1)]
        let mid = CurveEngine.warmth(forLux: 100, nodes: nodes)!
        XCTAssertLessThanOrEqual(mid, 0.3 + 1e-9,
                                 "a warmth point that rises with lux should be clamped to the running min")
    }

    func testStaysWithinRange() {
        let nodes = [node(10, 0.9), node(1_000, 0.2)]
        var lux = 10.0
        while lux <= 1_000 {
            let w = CurveEngine.warmth(forLux: lux, nodes: nodes)!
            XCTAssert(w >= 0.2 - 1e-9 && w <= 0.9 + 1e-9,
                      "interpolated warmth \(w) left [0.2, 0.9] at lux=\(lux)")
            lux += 5
        }
    }
}
