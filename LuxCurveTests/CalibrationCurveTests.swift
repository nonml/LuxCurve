//
//  CalibrationCurveTests.swift
//  LuxCurveTests
//
//  Covers the storage rules: sorting, the relative-tolerance upsert dedupe, and
//  the trust ordering between explicit (wizard) and learned (nudge) points.
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

    func testLearnedIsKeptAlongsideNearbyExplicit() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 100, brightness: 0.5, source: .explicit)
        ])
        curve.upsert(CalibrationNode(lux: 103, brightness: 0.9, source: .learned))
        // The learned point is collected as its own data point; the explicit one
        // is kept and never overwritten.
        XCTAssertEqual(curve.nodes.count, 2)
        let explicit = curve.nodes.first { $0.source == .explicit }
        XCTAssertEqual(explicit?.brightness, 0.5, "explicit point must be preserved")
        XCTAssertTrue(curve.nodes.contains { $0.source == .learned && $0.brightness == 0.9 })
    }

    func testLearnedReplacesNearbyLearnedButNotExplicit() {
        var curve = CalibrationCurve(nodes: [
            CalibrationNode(lux: 100, brightness: 0.5, source: .explicit),
            CalibrationNode(lux: 101, brightness: 0.6, source: .learned),
        ])
        // A new learned point near both replaces the learned one, keeps the explicit.
        curve.upsert(CalibrationNode(lux: 102, brightness: 0.8, source: .learned))
        XCTAssertEqual(curve.nodes.count, 2)
        XCTAssertTrue(curve.nodes.contains { $0.source == .explicit && $0.brightness == 0.5 })
        XCTAssertTrue(curve.nodes.contains { $0.source == .learned && $0.brightness == 0.8 })
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
