//
//  CurveEngineTests.swift
//  LuxCurveTests
//
//  Covers the pure interpolation engine: the no-calibration case, endpoint
//  clamping, that the curve passes through calibrated points, and the two
//  guarantees — monotonicity and no overshoot — across the lux range.
//

import XCTest
@testable import LuxCurve

final class CurveEngineTests: XCTestCase {

    private func node(_ lux: Double, _ b: Double) -> CalibrationNode {
        CalibrationNode(lux: lux, brightness: b)
    }

    func testNoNodesReturnsNil() {
        XCTAssertNil(CurveEngine.brightness(forLux: 100, nodes: []))
    }

    func testSingleNodeIsConstant() {
        let nodes = [node(50, 0.4)]
        XCTAssertEqual(CurveEngine.brightness(forLux: 0, nodes: nodes), 0.4)
        XCTAssertEqual(CurveEngine.brightness(forLux: 5_000, nodes: nodes), 0.4)
    }

    func testEndpointClamping() {
        let nodes = [node(10, 0.2), node(1_000, 0.8)]
        // Below the dimmest calibrated point -> floor at its brightness.
        XCTAssertEqual(CurveEngine.brightness(forLux: 0, nodes: nodes), 0.2)
        XCTAssertEqual(CurveEngine.brightness(forLux: 5, nodes: nodes), 0.2)
        // Above the brightest -> ceiling.
        XCTAssertEqual(CurveEngine.brightness(forLux: 10_000, nodes: nodes), 0.8)
    }

    func testPassesThroughCalibratedPoints() {
        let nodes = [node(10, 0.2), node(100, 0.5), node(1_000, 0.9)]
        for n in nodes {
            let y = CurveEngine.brightness(forLux: n.lux, nodes: nodes)
            XCTAssertEqual(y!, n.brightness, accuracy: 1e-9,
                           "curve should pass through its own nodes")
        }
    }

    func testMonotonicNonDecreasing() {
        let nodes = [node(5, 0.1), node(80, 0.55), node(400, 0.6), node(8_000, 0.95)]
        var previous = -1.0
        var lux = 0.0
        while lux <= 50_000 {
            let y = CurveEngine.brightness(forLux: lux, nodes: nodes)!
            XCTAssertGreaterThanOrEqual(y, previous - 1e-9,
                                        "brightness must never dip as lux rises (lux=\(lux))")
            previous = y
            lux += 25
        }
    }

    func testDippingNodesArePooledToTheirMean() {
        // A node that dips below an earlier one is pooled with it, so the two meet
        // at their mean rather than the dip being raised to the earlier value.
        let nodes = [node(10, 0.6), node(100, 0.3), node(1_000, 0.9)]
        XCTAssertEqual(CurveEngine.brightness(forLux: 10, nodes: nodes)!, 0.45, accuracy: 1e-9)
        XCTAssertEqual(CurveEngine.brightness(forLux: 100, nodes: nodes)!, 0.45, accuracy: 1e-9)
        XCTAssertEqual(CurveEngine.brightness(forLux: 1_000, nodes: nodes)!, 0.9, accuracy: 1e-9)
    }

    func testPoolingMergesAcrossBlocks() {
        // 0.5, 0.2 pool to 0.35; then 0.1 violates that block and all three pool.
        let fitted = CurveEngine.monotonic([(1, 0.5), (2, 0.2), (3, 0.1), (4, 0.8)])
        let values = fitted.map(\.value)
        XCTAssertEqual(values[0], 0.8 / 3, accuracy: 1e-9)
        XCTAssertEqual(values[1], 0.8 / 3, accuracy: 1e-9)
        XCTAssertEqual(values[2], 0.8 / 3, accuracy: 1e-9)
        XCTAssertEqual(values[3], 0.8, accuracy: 1e-9)
        XCTAssertEqual(fitted.map(\.lux), [1, 2, 3, 4])
    }

    func testMonotonicLeavesOrderedPointsUnchanged() {
        let points: [CurveEngine.Point] = [(1, 0.1), (2, 0.1), (3, 0.4)]
        XCTAssertEqual(CurveEngine.monotonic(points).map(\.value), [0.1, 0.1, 0.4])
    }

    func testNoOvershootBetweenPoints() {
        // Monotone cubic must stay within the bracketing nodes' values.
        let nodes = [node(10, 0.2), node(1_000, 0.8)]
        var lux = 10.0
        while lux <= 1_000 {
            let y = CurveEngine.brightness(forLux: lux, nodes: nodes)!
            XCTAssert(y >= 0.2 - 1e-9 && y <= 0.8 + 1e-9,
                      "interpolated value \(y) overshot [0.2, 0.8] at lux=\(lux)")
            lux += 5
        }
    }

    func testLogLuxIsIncreasingAndDefinedAtZero() {
        XCTAssertEqual(CurveEngine.logLux(0), 0, accuracy: 1e-12)
        XCTAssertGreaterThan(CurveEngine.logLux(1_000), CurveEngine.logLux(100))
    }
}
