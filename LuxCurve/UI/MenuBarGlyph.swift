//
//  MenuBarGlyph.swift
//  LuxCurve
//
//  The menu-bar icon, which reflects state at a glance:
//   * no sensor      → a warning triangle
//   * disabled       → an idle outline sun
//   * enabled & dim  → a small sun
//   * enabled & bright → a filled sun
//

import SwiftUI

struct MenuBarGlyph: View {
    @ObservedObject var daemon: DaemonManager
    let enabled: Bool

    var body: some View {
        Image(systemName: symbolName)
    }

    private var symbolName: String {
        if !daemon.sensorAvailable { return "exclamationmark.triangle" }
        if !enabled { return "sun.max" }
        return daemon.targetBrightness < 0.5 ? "sun.min" : "sun.max.fill"
    }
}

/// The menu-bar label: the glyph, plus a one-time action that opens the guided
/// calibration window the first time LuxCurve launches, so a new user starts in
/// the right place.
struct MenuBarLabel: View {
    @ObservedObject var daemon: DaemonManager
    let enabled: Bool

    @Environment(\.openWindow) private var openWindow
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    var body: some View {
        MenuBarGlyph(daemon: daemon, enabled: enabled)
            .task {
                guard !hasLaunchedBefore else { return }
                hasLaunchedBefore = true
                openWindow(id: WindowID.calibration)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}
