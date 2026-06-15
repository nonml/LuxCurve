//
//  SettingsView.swift
//  LuxCurve
//
//  The Settings window (⌘,): the adaptive toggles, response and brightness-range
//  controls, a suggested starting curve, and reset actions. Sliders commit when
//  the user releases them rather than on every frame, so we don't rewrite the
//  config file continuously.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var daemon: DaemonManager
    @EnvironmentObject private var loginItem: LoginItemManager
    @Environment(\.openWindow) private var openWindow

    @State private var minBrightness = 0.05
    @State private var maxBrightness = 1.0
    @State private var smoothing = 0.15
    @State private var overallScale = 1.0
    @State private var pending: PendingAction?

    private enum PendingAction: Identifiable {
        case suggested, resetBrightness, resetWarmth, resetEverything
        var id: Int { hashValue }
    }

    var body: some View {
        Form {
            Section("Adaptive") {
                Toggle("Adaptive brightness", isOn: Binding(
                    get: { model.isEnabled }, set: { model.setEnabled($0) }))
                if model.canControlWarmth {
                    Toggle("Adaptive warmth (color temperature)", isOn: Binding(
                        get: { model.isWarmthEnabled }, set: { model.setWarmthEnabled($0) }))
                }
                Toggle("Dim at night", isOn: Binding(
                    get: { model.isCircadianEnabled }, set: { model.setCircadianEnabled($0) }))
                    .help("Eases the screen down in the late evening and overnight, on top of your curve.")
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
            }

            Section("Response") {
                Slider(
                    value: $smoothing,
                    in: 0.03...0.6,
                    onEditingChanged: { editing in if !editing { model.setSmoothing(smoothing) } },
                    minimumValueLabel: Text("Smoother").font(.caption).foregroundStyle(.secondary),
                    maximumValueLabel: Text("Snappier").font(.caption).foregroundStyle(.secondary)
                ) {
                    Text("Responsiveness")
                }
                Text("How quickly the screen follows changes in lighting.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Brightness") {
                LabeledContent("Overall") {
                    HStack {
                        Slider(value: $overallScale, in: 0.5...1.5,
                               onEditingChanged: { editing in if !editing { model.setBrightnessScale(overallScale) } })
                        Text(percent(overallScale)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Dimmest") {
                    HStack {
                        Slider(value: $minBrightness, in: 0...1,
                               onEditingChanged: { editing in if !editing { commitLimits() } })
                        Text(percent(minBrightness)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Brightest") {
                    HStack {
                        Slider(value: $maxBrightness, in: 0...1,
                               onEditingChanged: { editing in if !editing { commitLimits() } })
                        Text(percent(maxBrightness)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Text("The curve is kept within these limits so it never drives the screen fully dark or to full glare.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Calibration") {
                Toggle("Learn from manual adjustments", isOn: Binding(
                    get: { model.learnsFromAdjustments }, set: { model.setLearnFromAdjustments($0) }))
                    .help("When on, a brightness change you settle on is collected as a calibration point for that lighting.")
                LabeledContent("Brightness points", value: "\(model.config.curve.nodes.count)")
                if model.canControlWarmth {
                    LabeledContent("Warmth points", value: "\(model.config.warmthCurve.nodes.count)")
                }
                Button {
                    openWindow(id: WindowID.calibration)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open calibration window…", systemImage: "slider.horizontal.3")
                }
                Button {
                    openWindow(id: WindowID.points)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Manage calibration points…", systemImage: "list.bullet")
                }
                .disabled(model.config.curve.isEmpty && model.config.warmthCurve.isEmpty)
                Button {
                    if model.config.curve.isEmpty { model.applySuggestedStartingCurve() }
                    else { pending = .suggested }
                } label: {
                    Label("Start from a suggested curve", systemImage: "wand.and.stars")
                }
                Text("Fills in a sensible baseline for typical lighting that you can then fine-tune by calibrating.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Reset") {
                Button("Reset brightness calibration") { pending = .resetBrightness }
                    .disabled(model.config.curve.isEmpty)
                if model.canControlWarmth {
                    Button("Reset warmth calibration") { pending = .resetWarmth }
                        .disabled(model.config.warmthCurve.isEmpty)
                }
                Button("Reset everything…", role: .destructive) { pending = .resetEverything }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 600)
        .onAppear { syncFromConfig() }
        .alert(alertTitle,
               isPresented: Binding(get: { pending != nil },
                                    set: { if !$0 { pending = nil } }),
               presenting: pending) { action in
            Button(confirmLabel(for: action),
                   role: action == .suggested ? nil : .destructive) {
                perform(action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(alertMessage(for: action))
        }
    }

    private func syncFromConfig() {
        minBrightness = model.config.minBrightness
        maxBrightness = model.config.maxBrightness
        smoothing = model.config.emaAlpha
        overallScale = model.config.brightnessScale
    }

    private func commitLimits() {
        model.setBrightnessLimits(min: minBrightness, max: maxBrightness)
        minBrightness = model.config.minBrightness   // reflect any clamping
        maxBrightness = model.config.maxBrightness
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .suggested:       model.applySuggestedStartingCurve()
        case .resetBrightness: model.resetBrightnessCalibration()
        case .resetWarmth:     model.resetWarmthCalibration()
        case .resetEverything: model.resetAll(); syncFromConfig()
        }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func confirmLabel(for action: PendingAction) -> String {
        switch action {
        case .suggested:       return "Replace"
        case .resetEverything: return "Reset Everything"
        default:               return "Reset"
        }
    }

    private var alertTitle: String {
        switch pending {
        case .suggested:       return "Replace your calibration with a suggested curve?"
        case .resetBrightness: return "Reset brightness calibration?"
        case .resetWarmth:     return "Reset warmth calibration?"
        case .resetEverything: return "Reset everything?"
        case .none:            return ""
        }
    }

    private func alertMessage(for action: PendingAction) -> String {
        switch action {
        case .suggested:
            return "This replaces your current brightness and warmth points with a suggested baseline. You can fine-tune it afterward."
        case .resetBrightness:
            return "This removes every brightness point. The screen is left alone until you calibrate again."
        case .resetWarmth:
            return "This removes every warmth point, turns adaptive warmth off, and returns the display to a neutral color."
        case .resetEverything:
            return "This restores all settings to their defaults and clears both the brightness and warmth calibration. This cannot be undone."
        }
    }
}
