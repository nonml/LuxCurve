//
//  CircadianTests.swift
//  LuxCurveTests
//
//  Covers the time-of-day brightness scale: full strength in daytime, the night
//  floor overnight, ramps in between, and that it always stays in [floor, 1].
//

import XCTest
@testable import LuxCurve

final class CircadianTests: XCTestCase {

    func testDaytimeIsFullStrength() {
        XCTAssertEqual(Circadian.scale(hour: 12), 1.0, accuracy: 1e-9)
        XCTAssertEqual(Circadian.scale(hour: 9), 1.0, accuracy: 1e-9)
        XCTAssertEqual(Circadian.scale(hour: 19), 1.0, accuracy: 1e-9)
    }

    func testNightIsAtFloor() {
        XCTAssertEqual(Circadian.scale(hour: 0), Circadian.nightFloor, accuracy: 1e-9)
        XCTAssertEqual(Circadian.scale(hour: 3), Circadian.nightFloor, accuracy: 1e-9)
        XCTAssertEqual(Circadian.scale(hour: 23.5), Circadian.nightFloor, accuracy: 1e-9)
    }

    func testDuskRampsDown() {
        let early = Circadian.scale(hour: 20.5)
        let late = Circadian.scale(hour: 22.5)
        XCTAssertLessThan(early, 1.0)
        XCTAssertGreaterThan(early, Circadian.nightFloor)
        XCTAssertLessThan(late, early, "dusk should keep easing down")
    }

    func testStaysInRange() {
        var h = 0.0
        while h < 24 {
            let s = Circadian.scale(hour: h)
            XCTAssert(s >= Circadian.nightFloor - 1e-9 && s <= 1.0 + 1e-9,
                      "scale \(s) out of range at hour \(h)")
            h += 0.1
        }
    }
}
