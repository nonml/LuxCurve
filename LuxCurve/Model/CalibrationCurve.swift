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

    /// Insert a node, replacing a same-kind point captured at nearly the same lux
    /// (so re-calibrating or re-adjusting the same lighting updates that point
    /// instead of piling up duplicates). Tolerance is relative because lux spans a
    /// huge range.
    ///
    /// Trust ordering:
    ///  - An `.explicit` point (deliberate wizard calibration) is authoritative: it
    ///    replaces any nearby point, learned or explicit.
    ///  - A `.learned` point (a settled manual adjustment) is collected as its own
    ///    data point. It updates a nearby *learned* point but is kept alongside a
    ///    nearby `.explicit` one — it never overwrites a deliberate calibration.
    mutating func upsert(_ node: CalibrationNode) {
        let tolerance = max(1.0, node.lux * 0.10)
        func nearby(_ other: CalibrationNode) -> Bool { abs(other.lux - node.lux) <= tolerance }

        if node.source == .explicit {
            nodes.removeAll(where: nearby)
        } else {
            nodes.removeAll { nearby($0) && $0.source == .learned }
        }
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
