//
//  CalibrationWizardView.swift
//  LuxCurve
//
//  The calibration window. The user adjusts a live slider (which changes the
//  real screen brightness) until the reference content is comfortable to read,
//  then saves a (current lux, chosen brightness) point.
//
//  Two faces, one window:
//   * Quick adjust — a single screen (reference canvas + live lux + slider +
//     curve graph + Save). This is the default and is meant to be reopened often
//     as the lighting changes, so the user builds up a curve over days.
//   * Guided intro — shown the first time only: a couple of coaching pages that
//     explain the idea and the one critical setup step (turning OFF macOS's own
//     automatic brightness), then hand off to the quick screen.
//
//  While this window is open the daemon is suspended (see AppModel.beginCalibration)
//  so it does not override the slider or learn from the live preview. Closing without
//  saving restores the brightness the user started with.
//

import SwiftUI

struct CalibrationWizardView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var daemon: DaemonManager
    @Environment(\.dismiss) private var dismiss

    /// Persisted across launches: once the user has been through the intro, every
    /// later open goes straight to quick adjust. App state, not calibration data,
    /// so it lives in UserDefaults rather than config.json.
    @AppStorage("hasSeenCalibrationGuide") private var hasSeenGuide = false

    @State private var sliderValue: Double = 0.5
    @State private var warmthValue: Double = 0.4
    @State private var didSave = false
    @State private var showingGuide = false
    @State private var guidePage = 0
    @State private var justSavedLux: Double?

    private let guidePages = GuidePage.all

    var body: some View {
        Group {
            if showingGuide {
                guidedIntro
            } else {
                quickAdjust
            }
        }
        .frame(width: 560, height: 620)
        .onAppear {
            let seed = model.beginCalibration()
            sliderValue = seed.brightness
            warmthValue = seed.warmth
            showingGuide = !hasSeenGuide
        }
        .onDisappear {
            // Restore the user's brightness unless they committed a point.
            model.endCalibration(restorePreviousBrightness: !didSave)
        }
    }

    // MARK: Guided intro (first run only)

    private var guidedIntro: some View {
        let page = guidePages[guidePage]
        return VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.symbol)
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
            Text(page.title)
                .font(.title2.bold())
            Text(page.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()

            HStack(spacing: 6) {
                ForEach(guidePages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == guidePage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            HStack {
                Button("Skip") { finishGuide() }
                    .buttonStyle(.borderless)
                Spacer()
                Button(guidePage == guidePages.count - 1 ? "Start calibrating" : "Continue") {
                    if guidePage == guidePages.count - 1 {
                        finishGuide()
                    } else {
                        guidePage += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
    }

    private func finishGuide() {
        hasSeenGuide = true
        showingGuide = false
    }

    // MARK: Quick adjust

    private var quickAdjust: some View {
        VStack(spacing: 0) {
            testCanvas
            Divider()
            controls
        }
    }

    // MARK: Reference content to judge eye comfort against

    private var testCanvas: some View {
        ScrollView {
            VStack(spacing: 18) {
                referenceCard(background: .white, foreground: .black, title: "Light document")
                referenceCard(background: .black, foreground: .white, title: "Dark mode")
                stepWedge
                gradientStrip
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func referenceCard(background: Color, foreground: Color, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(foreground.opacity(0.6))
            Text("The quick brown fox jumps over the lazy dog. 0123456789")
                .font(.system(size: 13))
                .foregroundStyle(foreground)
            Text("Small grey body text used to check for glare and eye strain when reading for a long time in this lighting.")
                .font(.system(size: 11))
                .foregroundStyle(foreground.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.3)))
    }

    /// Gamma-style step wedge: the darkest patches should be just distinguishable
    /// from black, the brightest just short of glaring.
    private var stepWedge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tone steps").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(0..<16, id: \.self) { i in
                    Rectangle().fill(Color(white: Double(i) / 15.0))
                }
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.3)))
        }
    }

    private var gradientStrip: some View {
        LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Live readings, graph, slider, save

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Label("\(Int(daemon.smoothedLux.rounded())) lux · \(CalibrationGuidance.label(forLux: daemon.smoothedLux))",
                      systemImage: "sun.max")
                if !daemon.sensorAvailable {
                    Text("· sensor unavailable").foregroundStyle(.orange)
                }
                Spacer()
                Text("Brightness \(Int((sliderValue * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if model.canControlWarmth {
                    Text("· Warmth \(Int((warmthValue * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            CurveGraph(nodes: model.config.curve.nodes,
                       minBrightness: model.config.minBrightness,
                       maxBrightness: model.config.maxBrightness,
                       currentLux: daemon.smoothedLux,
                       chosenBrightness: sliderValue)
                .frame(height: 96)

            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(value: $sliderValue, in: 0...1) { _ in }
                    .onChange(of: sliderValue) { _, newValue in
                        model.previewBrightness(newValue)
                        justSavedLux = nil
                    }
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.secondary)
            }

            if model.canControlWarmth {
                HStack(spacing: 10) {
                    Image(systemName: "snowflake")
                        .foregroundStyle(.secondary)
                    Slider(value: $warmthValue, in: 0...1) { _ in }
                        .onChange(of: warmthValue) { _, newValue in
                            model.previewWarmth(newValue)
                            justSavedLux = nil
                        }
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.secondary)
                }
            }

            suggestion

            footer
        }
        .padding(20)
    }

    /// A non-prescriptive starting point for the current lighting, plus a button
    /// to adopt it. The user still fine-tunes by eye. The numbers are a starting
    /// point, not a health figure; the note carries the research-backed guidance.
    private var suggestion: some View {
        let lux = daemon.smoothedLux
        let sb = CalibrationGuidance.suggestedBrightness(forLux: lux)
        let sw = CalibrationGuidance.suggestedWarmth(forLux: lux)
        var text = "Suggested start: about \(Int((sb * 100).rounded()))% brightness"
        if model.canControlWarmth { text += ", \(Int((sw * 100).rounded()))% warmth" }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use suggested") {
                    sliderValue = sb
                    model.previewBrightness(sb)
                    if model.canControlWarmth {
                        warmthValue = sw
                        model.previewWarmth(sw)
                    }
                    justSavedLux = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Text(CalibrationGuidance.note(forLux: lux))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let saved = justSavedLux {
            Label("Saved a point for \(Int(saved.rounded())) lux. "
                  + "Reopen this in different lighting to round out your curve.",
                  systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
        } else if model.config.curve.isEmpty {
            Text("This is your first point. Calibrate again in a few different "
                 + "lightings — bright day, lamp-lit evening, overcast — and "
                 + "LuxCurve fills in everything between.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            Text("Adjust until the text above is easy to read without glare, "
                 + "then save this point for the current lighting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }

        HStack {
            Button("Close") { dismiss() }
            Button("Show intro") {
                guidePage = 0
                showingGuide = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
            Button {
                let lux = daemon.smoothedLux
                model.saveCalibrationPoint(lux: lux,
                                           brightness: sliderValue,
                                           warmth: model.canControlWarmth ? warmthValue : nil)
                didSave = true
                justSavedLux = lux
            } label: {
                Label("Save Calibration Point", systemImage: "checkmark.circle.fill")
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Guided intro content

private struct GuidePage {
    let symbol: String
    let title: String
    let body: String

    static let all: [GuidePage] = [
        GuidePage(
            symbol: "sun.max.trianglebadge.exclamationmark",
            title: "Turn off automatic brightness",
            body: "In System Settings ▸ Displays, turn off “Automatically adjust "
                + "brightness.” This lets LuxCurve manage your display without "
                + "macOS adjusting it at the same time."
        ),
        GuidePage(
            symbol: "eye",
            title: "Adjust by eye",
            body: "Aim to match the screen to the room — bright enough to read "
                + "easily, but not glowing in a dark room. On supported Macs a "
                + "second slider warms the color; warmer light in the evening is "
                + "easier on the eyes and on sleep. LuxCurve suggests a starting "
                + "point for each lighting, then you fine-tune by eye."
        ),
        GuidePage(
            symbol: "chart.line.uptrend.xyaxis",
            title: "Build your curve",
            body: "Each time you save, LuxCurve records the current light level and "
                + "your chosen brightness. Calibrate in a few different lightings, "
                + "and LuxCurve sets the levels in between."
        ),
    ]
}
