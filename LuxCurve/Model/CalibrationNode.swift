//
//  CalibrationNode.swift
//  LuxCurve
//
//  One user-recorded calibration point: at `lux` ambient light, the user chose
//  `brightness` (0...1 linear) as comfortable. The calibration curve is an array
//  of these points, captured across a range of lighting conditions.
//

import Foundation

struct CalibrationNode: Codable, Equatable, Identifiable {

    /// How a point came to exist. Deliberate wizard calibration is trusted more
    /// than a point inferred from an ambient brightness nudge, so a `.learned`
    /// point is never allowed to overwrite an `.explicit` one (see
    /// `CalibrationCurve.upsert`).
    enum Source: String, Codable {
        case explicit   // saved from the calibration wizard
        case learned    // inferred from a manual brightness adjustment
    }

    var id: UUID
    var lux: Double         // >= 0
    var brightness: Double  // 0.0 ... 1.0 linear
    var source: Source

    init(id: UUID = UUID(), lux: Double, brightness: Double, source: Source = .explicit) {
        self.id = id
        self.lux = max(0, lux)
        self.brightness = min(1, max(0, brightness))
        self.source = source
    }

    // Tolerate configs written without an `id`/`source` (forward/backward compat).
    // Points from before this field existed were all explicit wizard saves.
    enum CodingKeys: String, CodingKey { case id, lux, brightness, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        let lux = try c.decode(Double.self, forKey: .lux)
        let brightness = try c.decode(Double.self, forKey: .brightness)
        let source = (try? c.decode(Source.self, forKey: .source)) ?? .explicit
        self.init(id: id, lux: lux, brightness: brightness, source: source)
    }
}
