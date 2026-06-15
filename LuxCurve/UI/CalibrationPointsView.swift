//
//  CalibrationPointsView.swift
//  LuxCurve
//
//  Lists the calibration points (brightness and warmth) so the user can see and
//  delete individual ones — e.g. to remove a stray learned point — without
//  resetting the whole curve.
//

import SwiftUI

struct CalibrationPointsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Brightness") {
                if model.config.curve.nodes.isEmpty {
                    Text("No brightness points yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.config.curve.nodes) { node in
                        pointRow(lux: node.lux, value: node.brightness, source: node.source) {
                            model.deletePoint(id: node.id)
                        }
                    }
                }
            }

            if model.canControlWarmth {
                Section("Warmth") {
                    if model.config.warmthCurve.nodes.isEmpty {
                        Text("No warmth points yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.config.warmthCurve.nodes) { node in
                            pointRow(lux: node.lux, value: node.brightness, source: node.source) {
                                model.deleteWarmthPoint(id: node.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 380, height: 460)
    }

    private func pointRow(lux: Double,
                          value: Double,
                          source: CalibrationNode.Source,
                          delete: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text("\(Int(lux.rounded())) lux").monospacedDigit()
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Text("\(Int((value * 100).rounded()))%").monospacedDigit()
            if source == .learned {
                Text("learned")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this point")
        }
    }
}
