//
//  LoginItemManager.swift
//  LuxCurve
//
//  Wraps SMAppService so LuxCurve can start itself at login. The service's own
//  registration status is the source of truth — we don't persist a copy in the
//  config — so the toggle always reflects reality even if the user changed it in
//  System Settings ▸ General ▸ Login Items.
//

import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {

    @Published private(set) var isEnabled: Bool = false

    init() {
        refresh()
    }

    /// Re-read the live registration status (call after toggling or on appear).
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister LuxCurve as a login item.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LuxCurve: failed to \(enabled ? "enable" : "disable") launch at login (\(error)).")
        }
        refresh()
    }
}
