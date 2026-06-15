//
//  EMAFilterTests.swift
//  LuxCurveTests
//
//  Covers the smoothing filter: seeding on first sample, the update recurrence,
//  alpha clamping, convergence toward a constant input, and reset.
//

import XCTest
@testable import LuxCurve

final class EMAFilterTests: XCTestCase {

    func testFirstSampleSeedsTheAverage() {
        var ema = EMAFilter(alpha: 0.15)
        XCTAssertNil(ema.value)
        XCTAssertEqual(ema.update(42), 42)
        XCTAssertEqual(ema.value, 42)
    }

    func testUpdateRecurrence() {
        var ema = EMAFilter(alpha: 0.5)
        XCTAssertEqual(ema.update(10), 10)          // seed
        XCTAssertEqual(ema.update(20), 15)          // 0.5*20 + 0.5*10
        XCTAssertEqual(ema.update(20), 17.5)        // 0.5*20 + 0.5*15
    }

    func testAlphaIsClamped() {
        XCTAssertEqual(EMAFilter(alpha: 5).alpha, 1)
        XCTAssertEqual(EMAFilter(alpha: -1).alpha, 0)
    }

    func testConvergesTowardConstant() {
        var ema = EMAFilter(alpha: 0.3)
        ema.update(0)
        for _ in 0..<200 { ema.update(100) }
        XCTAssertEqual(ema.value!, 100, accuracy: 0.01)
    }

    func testZeroAlphaHoldsTheSeed() {
        var ema = EMAFilter(alpha: 0)
        ema.update(7)
        XCTAssertEqual(ema.update(999), 7, "alpha 0 should ignore later samples")
    }

    func testReset() {
        var ema = EMAFilter(alpha: 0.2)
        ema.update(50)
        ema.reset()
        XCTAssertNil(ema.value)
        XCTAssertEqual(ema.update(3), 3, "after reset the next sample re-seeds")
    }
}
