//
//  CalibrationCurveTests.swift
//  LuxCurveTests
//
//  Covers the storage rules: sorting, the relative-tolerance upsert dedupe, and
//  that the newest point wins over nearby or contradicting points.
//

import XCTest
@testable import LuxCurve

final class CalibrationCurveTests: XCTestCase {

    func testInitSortsByLux() {
        let curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 1_000, brightness: 0.9),
            CalibrationNode(lux: 10, brightness: 0.2),
            CalibrationNode(lux: 100, brightness: 0.5),
        ])
        XCTAssertEqual(curve.nodes.map(\.lux), [10, 100, 1_000])
    }

    func testUpsertReplacesNearbyWithinTolerance() {
        var curve = CalibrationCurve(nodes: [CalibrationNode(lux: 100, brightness: 0.5)])
        // 105 is within the 10% relative tolerance of 100, so it replaces.
        curve.upsert(CalibrationNode(lux: 105, brightness: 0.7))
        XCTAssertEqual(curve.nodes.count, 1)
        XCTAssertEqual(curve.nodes[0].brightness, 0.7)
    }

    func testUpsertInsertsWhenFarApart() {
        var curve = CalibrationCurve(nodes: [CalibrationNode(lux: 100, brightness: 0.5)])
        curve.upsert(CalibrationNode(lux: 1_000, brightness: 0.9))
        XCTAssertEqual(curve.nodes.count, 2)
    }

    func testLearnedReplacesNearbyExplicit() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 100, brightness: 0.5, source: .explicit)
        ])
        curve.upsert(CalibrationNode(lux: 103, brightness: 0.3, source: .learned))
        // The most recent choice at this lighting wins, whatever its source.
        XCTAssertEqual(curve.nodes.count, 1)
        XCTAssertEqual(curve.nodes[0].brightness, 0.3)
        XCTAssertEqual(curve.nodes[0].source, .learned)
    }

    func testDimmerPointRemovesBrighterPointsAtLowerLux() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 10, brightness: 0.1),
            CalibrationNode(lux: 50, brightness: 0.4),
            CalibrationNode(lux: 1_000, brightness: 0.8),
        ])
        // Dimming to 0.2 at 200 lux contradicts the 0.4 point at 50 lux.
        curve.upsert(CalibrationNode(lux: 200, brightness: 0.2, source: .learned))
        XCTAssertEqual(curve.nodes.map(\.lux), [10, 200, 1_000])
        XCTAssertEqual(CurveEngine.brightness(forLux: 200, nodes: curve.nodes)!, 0.2, accuracy: 1e-9,
                       "the curve must reproduce the value the user just chose")
    }

    func testBrighterPointRemovesDimmerPointsAtHigherLux() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 10, brightness: 0.1),
            CalibrationNode(lux: 500, brightness: 0.3),
            CalibrationNode(lux: 5_000, brightness: 0.9),
        ])
        curve.upsert(CalibrationNode(lux: 100, brightness: 0.5, source: .learned))
        XCTAssertEqual(curve.nodes.map(\.lux), [10, 100, 5_000])
    }

    func testWarmthUpsertRemovesPointsInReverseDirection() {
        // Warmth falls as lux rises, so a cooler point at lower lux conflicts.
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 10, brightness: 0.9),
            CalibrationNode(lux: 50, brightness: 0.3),
            CalibrationNode(lux: 1_000, brightness: 0.1),
        ])
        curve.upsert(CalibrationNode(lux: 200, brightness: 0.6), risesWithLux: false)
        XCTAssertEqual(curve.nodes.map(\.lux), [10, 200, 1_000])
    }

    func testOrderedPointsAreKept() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 10, brightness: 0.1),
            CalibrationNode(lux: 1_000, brightness: 0.8),
        ])
        curve.upsert(CalibrationNode(lux: 100, brightness: 0.4, source: .learned))
        XCTAssertEqual(curve.nodes.count, 3)
    }

    func testExplicitReplacesNearbyLearned() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 100, brightness: 0.5, source: .learned)
        ])
        curve.upsert(CalibrationNode(lux: 103, brightness: 0.9, source: .explicit))
        XCTAssertEqual(curve.nodes.count, 1)
        XCTAssertEqual(curve.nodes[0].brightness, 0.9)
        XCTAssertEqual(curve.nodes[0].source, .explicit)
    }

    func testLearnedReplacesNearbyLearned() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 100, brightness: 0.5, source: .learned)
        ])
        curve.upsert(CalibrationNode(lux: 103, brightness: 0.9, source: .learned))
        XCTAssertEqual(curve.nodes.count, 1)
        XCTAssertEqual(curve.nodes[0].brightness, 0.9)
    }

    func testRemove() {
        let keep = CalibrationNode(lux: 100, brightness: 0.5)
        let drop = CalibrationNode(lux: 1_000, brightness: 0.9)
        var curve = CalibrationCurve(nodes: [keep, drop])
        curve.remove(id: drop.id)
        XCTAssertEqual(curve.nodes.map(\.id), [keep.id])
    }

    func testNodeClampsInputs() {
        let n = CalibrationNode(lux: -50, brightness: 1.4)
        XCTAssertEqual(n.lux, 0)
        XCTAssertEqual(n.brightness, 1.0)
    }
}
