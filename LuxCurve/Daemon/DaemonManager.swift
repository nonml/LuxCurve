//
//  DaemonManager.swift
//  LuxCurve
//
//  The background loop. On each tick it:
//    1. reads raw lux,
//    2. smooths it with an EMA in log-lux space,
//    3. asks CurveEngine for the target brightness,
//    4. applies it — but only if it moved more than a deadband (avoids churn),
//    5. watches for the user manually changing brightness; when they do, it
//       defers to them at that lighting and — once they *settle* on a value —
//       reports it as a "nudge" so AppModel can learn a calibration point.
//
//  Lives and runs on the main thread (driven by a main-runloop Timer); the
//  per-tick work is a couple of cheap synchronous calls.
//
//  Manual-override / learning policy:
//   * A manual change above `nudgeThreshold` starts an override: the daemon stops
//     applying the curve and holds the user's value at this lighting.
//   * The value is not learned the instant a key is pressed. The daemon waits
//     until it has held steady for `settleTicks`, then records it once. A brief
//     change the user immediately corrects never settles, so it does not affect
//     the curve.
//   * Learned points are tagged `.learned` and can't overwrite a deliberate
//     wizard `.explicit` point (see CalibrationCurve.upsert).
//   * The override ends when the lighting changes by more than
//     `overrideExitLogDelta`, handing control back to the (now-updated) curve.
//
//  Applied brightness is ramped over a short eased fade rather than set in a
//  single jump, so transitions read as gentle rather than snapping.
//

import Foundation
import Combine
import AppKit

@MainActor
final class DaemonManager: ObservableObject {

    // MARK: Live state (observed by the UI)

    @Published private(set) var rawLux: Double = 0
    @Published private(set) var smoothedLux: Double = 0
    @Published private(set) var targetBrightness: Double = 0
    @Published private(set) var targetWarmth: Double = 0
    @Published private(set) var actualBrightness: Double = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var sensorAvailable: Bool = true

    /// Whether this Mac exposes the system color-temperature (Night Shift) control.
    let canControlWarmth: Bool = LCCanControlWarmth()

    /// False when the built-in display can't be driven (e.g. clamshell mode with
    /// only an external display attached). We surface it and stop trying.
    @Published private(set) var canControlBrightness: Bool = true

    /// True while the calibration wizard owns the screen. The loop keeps reading
    /// lux (so the wizard shows live readings) but stops applying brightness and
    /// stops learning, so it does not override the user's slider or mistake the
    /// live preview for a manual adjustment.
    @Published private(set) var isSuspended: Bool = false

    // MARK: Collaborators / config

    private let sensor = ALSSensor()
    private let brightness = BrightnessController()
    private let warmth = WarmthController()
    private var ema: EMAFilter
    private var config: AppConfig

    /// The warmth value WE last wrote, or nil if we have never touched the display
    /// color temperature this session. Lets us return to neutral only when we were
    /// the ones who changed it.
    private var lastAppliedWarmth: Double?
    private let warmthDeadband = 0.02

    /// Called when the user appears to have manually changed brightness, with the
    /// current smoothed lux and the brightness they chose. AppModel turns this
    /// into a learned calibration point.
    var onManualNudge: ((_ lux: Double, _ brightness: Double) -> Void)?

    // MARK: Tick machinery

    private var timer: Timer?
    private let interval: TimeInterval = 1.5

    /// The brightness value WE last wrote, used to tell our own writes apart from
    /// the user's manual adjustments.
    private var lastAppliedBrightness: Double?
    /// Skip nudge-detection for one tick right after we write (the display takes
    /// a moment to report the new value back).
    private var ignoreNextDelta = false

    /// An in-progress manual override: the user changed brightness, so we defer to
    /// them at this lighting and learn the value once they settle on it.
    private struct Override {
        var value: Double      // brightness the user is currently holding
        var lux: Double        // smoothed lux when the override began
        var stableTicks: Int   // consecutive ticks the value has held steady
        var learned: Bool      // whether we've already recorded a point for it
    }
    private var manualOverride: Override?

    /// Deadbands and learning policy.
    private let applyDeadband = 0.01      // don't bother writing sub-1% changes
    private let nudgeThreshold = 0.03     // manual change must exceed this to count
    private let settleTicks = 2           // hold this many ticks (~3s) before learning
    private let settleEpsilon = 0.015     // movement below this counts as "holding"
    private let overrideExitLogDelta = 0.3 // log10-lux change (~2x) that ends an override

    /// Eased fade for applied brightness changes. The fade is far shorter than
    /// the tick interval, so it always finishes before the next tick.
    private var rampTimer: Timer?
    private var rampStep = 0
    private let rampDuration: TimeInterval = 0.45
    private let rampSteps = 15

    /// Observers for wake-from-sleep and display reconfiguration. Mutated only on
    /// the main actor; read once in `deinit` (nonisolated) after all other
    /// references are gone, so there's no actual race.
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []

    init(config: AppConfig) {
        self.config = config
        self.ema = EMAFilter(alpha: config.emaAlpha)
        registerLifecycleObservers()
    }

    deinit {
        let ws = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        for o in lifecycleObservers { ws.removeObserver(o); nc.removeObserver(o) }
    }

    // MARK: Display / power lifecycle

    /// Re-assert the curve after events that can leave the screen on a stale
    /// brightness or change which display we're driving.
    private func registerLifecycleObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        lifecycleObservers.append(
            ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                // The queue is .main, so we're on the main actor here.
                MainActor.assumeIsolated {
                    // Lighting may differ significantly after sleep, so reset the
                    // EMA and apply the current reading instead of easing from the
                    // pre-sleep value.
                    self?.ema.reset()
                    self?.reassert()
                }
            }
        )
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                // A display was connected/disconnected or the lid opened/closed.
                MainActor.assumeIsolated {
                    self?.reassert()
                }
            }
        )
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                // Don't leave the screen tinted after the app quits.
                MainActor.assumeIsolated {
                    self?.restoreNeutralWarmth()
                }
            }
        )
    }

    /// Run a tick now if we're live and not handing control to the wizard.
    private func reassert() {
        guard isRunning, !isSuspended else { return }
        tick()
    }

    // MARK: Control

    func updateConfig(_ config: AppConfig) {
        let alphaChanged = self.config.emaAlpha != config.emaAlpha
        self.config = config
        if alphaChanged { ema = EMAFilter(alpha: config.emaAlpha) }
    }

    func start() {
        guard timer == nil else { return }
        isRunning = true
        tick() // apply immediately so there's no visible lag on enable
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Added to RunLoop.main below, so this fires on the main actor.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        rampTimer?.invalidate()
        rampTimer = nil
        isRunning = false
        manualOverride = nil
        restoreNeutralWarmth()
    }

    /// Run a tick now so a settings change (scale, circadian, rails) takes effect
    /// immediately rather than on the next tick.
    func reapplyNow() {
        guard isRunning, !isSuspended else { return }
        tick()
    }

    /// Re-evaluate warmth right now — used when the warmth setting is toggled so
    /// the change takes effect immediately rather than on the next tick.
    func warmthSettingChanged() {
        guard isRunning, !isSuspended else {
            if !config.warmthEnabled { restoreNeutralWarmth() }
            return
        }
        reconcileWarmth(atLux: smoothedLux)
    }

    /// Pause applying/learning while the calibration wizard drives brightness.
    func suspend() {
        isSuspended = true
        rampTimer?.invalidate()
        rampTimer = nil
        manualOverride = nil
    }

    /// Resume normal operation. The first tick after this is exempt from nudge
    /// detection so the brightness we (or the wizard) just set isn't mislearned.
    func resume() {
        isSuspended = false
        ignoreNextDelta = true
        // The wizard may have driven warmth directly while suspended, so forget
        // our last applied value to force a fresh write on the next reconcile.
        lastAppliedWarmth = nil
    }

    // MARK: The loop

    private func tick() {
        guard let lux = sensor.currentLux() else {
            sensorAvailable = false
            return
        }
        sensorAvailable = true
        rawLux = lux

        let smoothedLog = ema.update(CurveEngine.logLux(lux))
        let smoothed = pow(10, smoothedLog) - 1
        smoothedLux = smoothed

        let actual = brightness.current() ?? lastAppliedBrightness ?? 0
        actualBrightness = actual

        // While the wizard is calibrating, surface the target for its graph but
        // don't apply it or learn from the live preview.
        if isSuspended {
            if let rawTarget = CurveEngine.brightness(forLux: smoothed,
                                                      nodes: config.curve.nodes) {
                targetBrightness = min(config.maxBrightness, max(config.minBrightness, rawTarget))
            }
            return
        }

        // If there's no built-in display to drive (e.g. clamshell with only an
        // external monitor), don't try to apply or learn — just wait it out.
        canControlBrightness = brightness.canControl
        if !canControlBrightness {
            manualOverride = nil
            return
        }

        // Color temperature tracks lighting independently of any brightness
        // override, so reconcile it every tick.
        reconcileWarmth(atLux: smoothed)

        updateManualOverride(actual: actual, atLux: smoothed)

        // While the user holds a manual override, defer to their value entirely —
        // don't apply the curve at this lighting.
        if let ov = manualOverride {
            targetBrightness = ov.value
            return
        }

        guard let rawTarget = CurveEngine.brightness(forLux: smoothed,
                                                     nodes: config.curve.nodes) else {
            // No calibration yet -> never touch the user's brightness.
            targetBrightness = actual
            return
        }
        // Apply the global brightness scale and the optional time-of-day dimming
        // on top of the curve, then clamp to the safety rails.
        let circadian = config.circadianEnabled ? Circadian.scale(for: Date()) : 1.0
        let scaled = rawTarget * config.brightnessScale * circadian
        let target = min(config.maxBrightness, max(config.minBrightness, scaled))
        targetBrightness = target

        if config.enabled, abs(target - actual) > applyDeadband {
            applyRamped(from: actual, to: target)
        }
    }

    /// Ease brightness from `start` to `target` over a short fade instead of a
    /// single hard write. We claim the destination as `lastAppliedBrightness`
    /// up front so the ramp's own writes aren't mistaken for a manual nudge.
    private func applyRamped(from start: Double, to target: Double) {
        rampTimer?.invalidate()
        lastAppliedBrightness = target
        ignoreNextDelta = true

        let delta = target - start
        rampStep = 0
        let t = Timer(timeInterval: rampDuration / Double(rampSteps), repeats: true) { [weak self] timer in
            // Added to RunLoop.main below, so this fires on the main actor.
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.rampStep += 1
                let p = Double(self.rampStep) / Double(self.rampSteps)
                // ease-in-out so the fade starts and ends gently
                let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
                self.brightness.set(start + delta * eased)
                if self.rampStep >= self.rampSteps {
                    self.brightness.set(target)
                    self.rampTimer?.invalidate()
                    self.rampTimer = nil
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        rampTimer = t
    }

    /// Drive the display color temperature from the warmth curve. Applies only
    /// when warmth is enabled, the master switch is on, and points are calibrated;
    /// otherwise it returns the display to neutral if we had tinted it.
    private func reconcileWarmth(atLux lux: Double) {
        guard canControlWarmth, config.enabled, config.warmthEnabled,
              let raw = CurveEngine.warmth(forLux: lux, nodes: config.warmthCurve.nodes) else {
            restoreNeutralWarmth()
            return
        }
        let target = min(1, max(0, raw))
        targetWarmth = target
        if let last = lastAppliedWarmth, abs(target - last) <= warmthDeadband { return }
        warmth.set(target)
        lastAppliedWarmth = target
    }

    /// Return the display to a neutral color temperature, but only if we were the
    /// one who changed it (so we never stomp the user's own Night Shift schedule
    /// when warmth was never active).
    private func restoreNeutralWarmth() {
        guard lastAppliedWarmth != nil else { return }
        warmth.disable()
        lastAppliedWarmth = nil
        targetWarmth = 0
    }

    /// Track manual brightness changes: enter an override when the user moves off
    /// what we applied, follow them while they adjust, learn the value once it
    /// settles, and end the override when the lighting changes enough.
    private func updateManualOverride(actual: Double, atLux lux: Double) {
        // Don't react to the brightness we ourselves just wrote.
        if ignoreNextDelta {
            ignoreNextDelta = false
            return
        }

        if var ov = manualOverride {
            // Lighting moved enough -> hand control back to the curve.
            if abs(CurveEngine.logLux(lux) - CurveEngine.logLux(ov.lux)) > overrideExitLogDelta {
                manualOverride = nil
                return
            }
            if abs(actual - ov.value) > settleEpsilon {
                // Still adjusting: follow the new value and restart the settle timer.
                ov.value = actual
                ov.stableTicks = 0
                ov.learned = false
            } else {
                // Holding steady.
                ov.value = actual
                ov.stableTicks += 1
                if !ov.learned, ov.stableTicks >= settleTicks {
                    ov.learned = true
                    onManualNudge?(ov.lux, actual)   // learn once, at the settled value
                }
            }
            manualOverride = ov
            return
        }

        // Not deferring yet: did the user just move off what we applied?
        guard let applied = lastAppliedBrightness, abs(actual - applied) > nudgeThreshold else { return }
        manualOverride = Override(value: actual, lux: lux, stableTicks: 0, learned: false)
    }
}
