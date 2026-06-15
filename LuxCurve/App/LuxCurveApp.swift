//
//  LuxCurveApp.swift
//  LuxCurve
//
//  Entry point. Runs headless in the menu bar (LSUIElement = YES, set in build
//  settings) with a popover, plus a separate window for the calibration wizard.
//

import SwiftUI

@main
struct LuxCurveApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var loginItem = LoginItemManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(model.daemon)
                .environmentObject(loginItem)
        } label: {
            MenuBarLabel(daemon: model.daemon, enabled: model.isEnabled)
        }
        .menuBarExtraStyle(.window)

        Window("Calibrate Lighting", id: WindowID.calibration) {
            CalibrationWizardView()
                .environmentObject(model)
                .environmentObject(model.daemon)
        }
        .windowResizability(.contentSize)

        Window("Calibration Points", id: WindowID.points) {
            CalibrationPointsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.daemon)
                .environmentObject(loginItem)
        }
    }
}

enum WindowID {
    static let calibration = "calibration"
    static let points = "points"
}
