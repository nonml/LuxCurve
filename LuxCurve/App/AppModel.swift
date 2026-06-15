//
//  AppModel.swift
//  LuxCurve
//
//  Top-level app state. Owns the config and the daemon, persists changes, and
//  exposes the handful of actions the UI triggers. Views observe `daemon` for
//  live readings and this model for config/actions.
//

import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var config: AppConfig
    let daemon: DaemonManager

    private let store = ConfigManager.shared

    init() {
        let loaded = store.load()
        self.config = loaded
        self.daemon = DaemonManager(config: loaded)

        // A manual brightness nudge becomes a learned calibration point.
        daemon.onManualNudge = { [weak self] lux, brightness in
            self?.learn(lux: lux, brightness: brightness)
        }

        if loaded.enabled { daemon.start() }
    }

    // MARK: Master toggle

    var isEnabled: Bool { config.enabled }

    func setEnabled(_ enabled: Bool) {
        config.enabled = enabled
        persist()
        if enabled { daemon.start() } else { daemon.stop() }
    }

    // MARK: Adaptive warmth

    /// Whether this Mac can drive color temperature at all (drives UI visibility).
    var canControlWarmth: Bool { daemon.canControlWarmth }

    var isWarmthEnabled: Bool { config.warmthEnabled }

    func setWarmthEnabled(_ enabled: Bool) {
        config.warmthEnabled = enabled
        persist()
        daemon.updateConfig(config)
        daemon.warmthSettingChanged()
    }

    // MARK: Calibration

    /// Record an explicit calibration point (from the wizard's Save button). Saves
    /// the brightness point and, when provided, a warmth point at the same lighting.
    /// Calibrating a warmth point turns adaptive warmth on so the user sees it work.
    func saveCalibrationPoint(lux: Double, brightness: Double, warmth: Double? = nil) {
        config.curve.upsert(CalibrationNode(lux: lux, brightness: brightness))
        if let warmth, canControlWarmth {
            config.warmthCurve.upsert(CalibrationNode(lux: lux, brightness: warmth))
            config.warmthEnabled = true
        }
        persist()
        daemon.updateConfig(config)
        calibrationOriginalBrightness = nil
    }

    /// Record a point learned from a manual brightness adjustment. The daemon only
    /// calls this once the user has *settled* on a value (it debounces the live
    /// adjustment), so this is a deliberate-ish choice. It's collected as a
    /// `.learned` point alongside any explicit calibration.
    ///
    /// The applied brightness already includes the overall scale and any circadian
    /// dimming, so we divide those out and store the baseline value — that way the
    /// stored point, re-scaled under the same conditions, reproduces what the user
    /// actually chose, and the curve stays a clean lux→brightness mapping.
    func learn(lux: Double, brightness: Double) {
        guard config.learnFromAdjustments else { return }
        let circadian = config.circadianEnabled ? Circadian.scale(for: Date()) : 1.0
        let factor = config.brightnessScale * circadian
        let baseline = factor > 0 ? brightness / factor : brightness
        config.curve.upsert(CalibrationNode(lux: lux, brightness: baseline, source: .learned))
        persist()
        daemon.updateConfig(config)
    }

    var learnsFromAdjustments: Bool { config.learnFromAdjustments }

    func setLearnFromAdjustments(_ enabled: Bool) {
        config.learnFromAdjustments = enabled
        persist()
        daemon.updateConfig(config)
    }

    func deletePoint(id: UUID) {
        config.curve.remove(id: id)
        persist()
        daemon.updateConfig(config)
    }

    func deleteWarmthPoint(id: UUID) {
        config.warmthCurve.remove(id: id)
        persist()
        daemon.updateConfig(config)
        daemon.warmthSettingChanged()
    }

    /// Replace the curves with a sensible baseline the user can then fine-tune,
    /// so they start from somewhere reasonable instead of a blank curve. Enables
    /// warmth when the Mac supports it.
    func applySuggestedStartingCurve() {
        config.curve = CalibrationCurve(nodes: CalibrationGuidance.suggestedBrightnessNodes())
        if canControlWarmth {
            config.warmthCurve = CalibrationCurve(nodes: CalibrationGuidance.suggestedWarmthNodes())
            config.warmthEnabled = true
        }
        persist()
        daemon.updateConfig(config)
        daemon.warmthSettingChanged()
    }

    // MARK: Reset / quality-of-life actions

    /// Forget the brightness curve. The screen is left alone until re-calibrated.
    func resetBrightnessCalibration() {
        config.curve.removeAll()
        persist()
        daemon.updateConfig(config)
    }

    /// Forget the warmth curve and turn adaptive warmth off, returning the display
    /// to a neutral color temperature.
    func resetWarmthCalibration() {
        config.warmthCurve.removeAll()
        config.warmthEnabled = false
        persist()
        daemon.updateConfig(config)
        daemon.warmthSettingChanged()
    }

    /// Restore everything to defaults: clears both curves and all settings.
    func resetAll() {
        let wasEnabled = config.enabled
        config = .default
        persist()
        daemon.updateConfig(config)
        daemon.warmthSettingChanged()
        if config.enabled, !wasEnabled { daemon.start() }
    }

    // MARK: Settings

    /// Smoothing factor (0...1). Lower reacts more slowly and steadily.
    func setSmoothing(_ alpha: Double) {
        config.emaAlpha = min(1, max(0.01, alpha))
        persist()
        daemon.updateConfig(config)
    }

    /// Brightness safety rails. `min` is kept below `max`.
    func setBrightnessLimits(min minValue: Double, max maxValue: Double) {
        let lo = Swift.max(0, Swift.min(minValue, maxValue))
        let hi = Swift.min(1, Swift.max(minValue, maxValue))
        config.minBrightness = lo
        config.maxBrightness = hi
        persist()
        daemon.updateConfig(config)
        daemon.reapplyNow()
    }

    /// Overall brightness multiplier on top of the curve (0.5...1.5).
    func setBrightnessScale(_ scale: Double) {
        config.brightnessScale = min(1.5, max(0.5, scale))
        persist()
        daemon.updateConfig(config)
        daemon.reapplyNow()
    }

    /// Time-of-day dimming on top of the curve.
    func setCircadianEnabled(_ enabled: Bool) {
        config.circadianEnabled = enabled
        persist()
        daemon.updateConfig(config)
        daemon.reapplyNow()
    }

    var isCircadianEnabled: Bool { config.circadianEnabled }

    // MARK: Wizard calibration session

    /// Brightness the screen was at when the wizard opened, restored if the user
    /// cancels without saving. nil means "nothing to restore" (no session, or the
    /// user already committed a point).
    private var calibrationOriginalBrightness: Double?
    private let brightnessController = BrightnessController()
    private let warmthController = WarmthController()

    /// Begin a calibration session: pause the daemon so it does not override the
    /// sliders or learn from the live preview, and remember the current brightness
    /// so it can be restored on cancel. Returns values to seed the sliders with:
    /// the current screen brightness, and the warmth the curve would use here.
    func beginCalibration() -> (brightness: Double, warmth: Double) {
        daemon.suspend()
        let brightness = brightnessController.current() ?? daemon.targetBrightness
        calibrationOriginalBrightness = brightness
        let warmth = CurveEngine.warmth(forLux: daemon.smoothedLux, nodes: config.warmthCurve.nodes)
            ?? CalibrationGuidance.suggestedWarmth(forLux: daemon.smoothedLux)
        return (brightness, warmth)
    }

    /// While the wizard's brightness slider moves, drive the real screen so the
    /// user calibrates against what they actually see. This does not persist.
    func previewBrightness(_ value: Double) {
        brightnessController.set(value)
    }

    /// While the wizard's warmth slider moves, drive the real color temperature.
    func previewWarmth(_ value: Double) {
        warmthController.set(value)
    }

    /// End a calibration session. If `restorePreviousBrightness` is true and the
    /// user never committed a point, put the screen back the way they found it.
    /// Either way, clear any live warmth preview and hand control back to the
    /// daemon, which re-applies the (possibly updated) warmth curve.
    func endCalibration(restorePreviousBrightness: Bool) {
        if restorePreviousBrightness, let original = calibrationOriginalBrightness {
            brightnessController.set(original)
        }
        calibrationOriginalBrightness = nil
        daemon.resume()
        // Clear the live preview tint, then let the daemon re-apply warmth from
        // the curve (or leave it neutral if warmth is off / uncalibrated).
        warmthController.disable()
        daemon.warmthSettingChanged()
    }

    // MARK: Persistence

    private func persist() {
        store.save(config)
    }
}
