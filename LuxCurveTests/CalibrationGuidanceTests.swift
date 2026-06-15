//
//  CalibrationGuidanceTests.swift
//  LuxCurveTests
//
//  Covers the baseline guidance: band labels at representative lux, and that the
//  suggested values behave like the real curves — brightness rises with lux,
//  warmth falls with lux, and everything stays in range.
//

import XCTest
@testable import LuxCurve

final class CalibrationGuidanceTests: XCTestCase {

    func testLabelsForRepresentativeLux() {
        XCTAssertEqual(CalibrationGuidance.label(forLux: 4), "Night / very dim")
        XCTAssertEqual(CalibrationGuidance.label(forLux: 110), "Indoor / living room")
        XCTAssertEqual(CalibrationGuidance.label(forLux: 350), "Office / bright indoor")
        XCTAssertEqual(CalibrationGuidance.label(forLux: 50_000), "Direct daylight")
    }

    func testSuggestedBrightnessRisesWithLux() {
        var previous = -1.0
        var lux = 0.0
        while lux <= 50_000 {
            let b = CalibrationGuidance.suggestedBrightness(forLux: lux)
            XCTAssert(b >= 0 && b <= 1, "brightness out of range at lux=\(lux): \(b)")
            XCTAssertGreaterThanOrEqual(b, previous - 1e-9,
                                        "suggested brightness must not dip as lux rises (lux=\(lux))")
            previous = b
            lux += 50
        }
    }

    func testSuggestedWarmthFallsWithLux() {
        var previous = 2.0
        var lux = 0.0
        while lux <= 50_000 {
            let w = CalibrationGuidance.suggestedWarmth(forLux: lux)
            XCTAssert(w >= 0 && w <= 1, "warmth out of range at lux=\(lux): \(w)")
            XCTAssertLessThanOrEqual(w, previous + 1e-9,
                                     "suggested warmth must not rise as lux rises (lux=\(lux))")
            previous = w
            lux += 50
        }
    }

    func testSuggestedNodesAreUsableCurves() {
        let bright = CalibrationGuidance.suggestedBrightnessNodes()
        let warm = CalibrationGuidance.suggestedWarmthNodes()
        XCTAssertEqual(bright.count, CalibrationGuidance.bands.count)
        XCTAssertEqual(warm.count, CalibrationGuidance.bands.count)
        // Both must produce a value through the engine (non-nil, in range).
        let b = CurveEngine.brightness(forLux: 300, nodes: bright)
        let w = CurveEngine.warmth(forLux: 300, nodes: warm)
        XCTAssertNotNil(b)
        XCTAssertNotNil(w)
        XCTAssert((0...1).contains(b!) && (0...1).contains(w!))
    }
}
