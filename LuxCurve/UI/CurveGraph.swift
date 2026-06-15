//
//  CurveGraph.swift
//  LuxCurve
//
//  A small read-only plot of the user's comfort curve: brightness (y, 0...1)
//  against ambient light (x, log-lux). It draws the same curve the daemon would
//  follow (via CurveEngine, clamped to the safety rails) plus the user's recorded
//  points, and — during calibration — a live marker showing where the point they
//  are about to save will land.
//
//  Purely presentational; it owns no state and does no IO.
//

import SwiftUI

struct CurveGraph: View {
    let nodes: [CalibrationNode]
    let minBrightness: Double
    let maxBrightness: Double

    /// Live calibration overlay. When `currentLux` is non-nil a vertical "now"
    /// guide is drawn; when `chosenBrightness` is also non-nil, the candidate
    /// point is highlighted where the two meet.
    var currentLux: Double? = nil
    var chosenBrightness: Double? = nil

    /// Right edge of the x axis, in lux. Daylight near a window is ~10k lux;
    /// 100k gives headroom while keeping the indoor range readable.
    private let axisMaxLux: Double = 100_000

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: 1, dy: 1)
            ZStack {
                railsAndGrid(in: rect)
                curvePath(in: rect)
                nodeDots(in: rect)
                liveMarker(in: rect)
            }
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
        .overlay(alignment: .bottomLeading) { axisLabel("dim") }
        .overlay(alignment: .bottomTrailing) { axisLabel("bright") }
    }

    // MARK: Coordinate mapping (log-lux -> x, brightness -> y)

    private var axisMaxLog: Double { CurveEngine.logLux(axisMaxLux) }

    private func point(lux: Double, brightness: Double, in rect: CGRect) -> CGPoint {
        let xNorm = min(1, max(0, CurveEngine.logLux(lux) / axisMaxLog))
        let yNorm = min(1, max(0, brightness))
        return CGPoint(x: rect.minX + xNorm * rect.width,
                       y: rect.maxY - yNorm * rect.height)
    }

    // MARK: Layers

    private func railsAndGrid(in rect: CGRect) -> some View {
        Path { p in
            for frac in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let y = rect.maxY - frac * rect.height
                p.move(to: CGPoint(x: rect.minX, y: y))
                p.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(.gray.opacity(0.15), lineWidth: 0.5)
    }

    @ViewBuilder
    private func curvePath(in rect: CGRect) -> some View {
        if nodes.isEmpty {
            EmptyView()
        } else {
            let samples = 64
            Path { p in
                for i in 0...samples {
                    let xNorm = Double(i) / Double(samples)
                    let lux = pow(10, xNorm * axisMaxLog) - 1
                    let raw = CurveEngine.brightness(forLux: lux, nodes: nodes) ?? 0
                    let b = min(maxBrightness, max(minBrightness, raw))
                    let pt = point(lux: lux, brightness: b, in: rect)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }

    private func nodeDots(in rect: CGRect) -> some View {
        ForEach(nodes) { node in
            let pt = point(lux: node.lux, brightness: node.brightness, in: rect)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                .position(pt)
        }
    }

    @ViewBuilder
    private func liveMarker(in rect: CGRect) -> some View {
        if let lux = currentLux {
            let xNorm = min(1, max(0, CurveEngine.logLux(lux) / axisMaxLog))
            let x = rect.minX + xNorm * rect.width
            Path { p in
                p.move(to: CGPoint(x: x, y: rect.minY))
                p.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            .stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            if let brightness = chosenBrightness {
                let pt = point(lux: lux, brightness: brightness, in: rect)
                Circle()
                    .fill(.orange)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                    .position(pt)
            }
        }
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .padding(4)
    }
}
