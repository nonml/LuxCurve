//
//  MedianWindowTests.swift
//  LuxCurveTests
//
//  Covers the short median used to estimate current lighting: odd and even
//  counts, eviction of old samples, and rejection of a single spike.
//

import XCTest
@testable import LuxCurve

final class MedianWindowTests: XCTestCase {

    func testEmptyHasNoMedian() {
        XCTAssertNil(MedianWindow(capacity: 5).median)
    }

    func testOddAndEvenCounts() {
        var w = MedianWindow(capacity: 5)
        w.push(3); w.push(1); w.push(2)
        XCTAssertEqual(w.median, 2)
        w.push(4)
        XCTAssertEqual(w.median, 2.5)
    }

    func testOldSamplesAreEvicted() {
        var w = MedianWindow(capacity: 3)
        for x in [1.0, 1.0, 1.0, 5.0, 5.0] { w.push(x) }
        XCTAssertEqual(w.samples, [1, 5, 5])
        XCTAssertEqual(w.median, 5)
    }

    func testSingleSpikeIsIgnored() {
        var w = MedianWindow(capacity: 5)
        for x in [2.0, 2.0, 0.1, 2.0, 2.0] { w.push(x) }
        XCTAssertEqual(w.median, 2)
    }

    func testReset() {
        var w = MedianWindow(capacity: 5)
        w.push(1)
        w.reset()
        XCTAssertNil(w.median)
    }
}
