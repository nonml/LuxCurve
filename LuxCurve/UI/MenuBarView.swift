//
//  MenuBarView.swift
//  LuxCurve
//
//  The menu-bar popover: live readings, the adaptive toggles, and entry points to
//  the calibration window and Settings.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var daemon: DaemonManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LuxCurve")
                .font(.headline)

            if !daemon.sensorAvailable {
                notice("This Mac has no readable light sensor, so there is nothing to adapt to.")
            } else if !daemon.canControlBrightness {
                notice("The built-in display is unreachable. Paused until it returns.")
            }

            if model.config.curve.isEmpty {
                Text("Not calibrated yet. Calibrate once in the current lighting, then a few more times across the day to build your curve.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                reading("Room lighting", value: "\(Int(daemon.smoothedLux.rounded())) lux")
                reading("Target brightness", value: "\(Int((daemon.targetBrightness * 100).rounded()))%")
                if model.canControlWarmth && model.isWarmthEnabled {
                    reading("Target warmth", value: "\(Int((daemon.targetWarmth * 100).rounded()))%")
                }
            }

            Toggle("Adaptive brightness", isOn: Binding(
                get: { model.isEnabled },
                set: { model.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .help("Master switch. Turn LuxCurve's adapting on or off. Warmth, login, and other options are in Settings.")

            Divider()

            Button {
                openWindow(id: WindowID.calibration)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Calibrate this lighting…", systemImage: "slider.horizontal.3")
            }

            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })

            HStack {
                Text(calibrationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var calibrationSummary: String {
        let count = model.config.curve.nodes.count
        switch count {
        case 0:  return "Not calibrated yet"
        case 1:  return "1 point saved"
        default: return "\(count) points saved"
        }
    }

    private func reading(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
