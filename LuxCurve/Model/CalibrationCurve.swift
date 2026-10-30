//
//  CalibrationCurve.swift
//  LuxCurve
//
//  The collection of calibration nodes, always kept sorted by lux. This is pure
//  storage — the math (interpolation, monotonic clamping) lives in CurveEngine.
//

import Foundation

struct CalibrationCurve: Codable, Equatable {
    private(set) var nodes: [CalibrationNode]

    init(nodes: [CalibrationNode] = []) {
        self.nodes = nodes.sorted { $0.lux < $1.lux }
    }

    var isEmpty: Bool { nodes.isEmpty }

    /// Insert a node as the user's current preference at its lighting. The most
    /// recent point wins, whether it came from the wizard (`.explicit`) or from a
    /// settled manual adjustment (`.learned`):
    ///
    ///  - A point captured at nearly the same lux is replaced, so re-calibrating
    ///    or re-adjusting the same lighting updates that point instead of piling up
    ///    duplicates. Tolerance is relative because lux spans a huge range.
    ///  - A point that contradicts the new one in the curve's direction is
    ///    removed. For brightness (`risesWithLux` true) that is a brighter point at
    ///    lower lux or a dimmer point at higher lux; warmth runs the other way.
    ///    Without this, CurveEngine's monotonic fit would pull the new point
    ///    toward the older ones and the curve would not reproduce what the user
    ///    just chose.
    ///
    /// If the stored points were in order before the insert, they still are after.
    mutating func upsert(_ node: CalibrationNode, risesWithLux: Bool = true) {
        let tolerance = max(1.0, node.lux * 0.10)
        func nearby(_ other: CalibrationNode) -> Bool { abs(other.lux - node.lux) <= tolerance }
        func conflicts(_ other: CalibrationNode) -> Bool {
            let lower = other.lux < node.lux
            let higherValue = other.brightness > node.brightness
            let lowerValue = other.brightness < node.brightness
            return risesWithLux
                ? (lower && higherValue) || (!lower && lowerValue)
                : (lower && lowerValue) || (!lower && higherValue)
        }

        nodes.removeAll { nearby($0) || conflicts($0) }
        nodes.append(node)
        nodes.sort { $0.lux < $1.lux }
    }

    mutating func remove(id: UUID) {
        nodes.removeAll { $0.id == id }
    }

    mutating func removeAll() {
        nodes.removeAll()
    }
}
