//
//  LaunchAtLogin.swift
//  AppPocket
//
//  Registration as a login item, via the modern `SMAppService` API.
//

import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    ///
    /// This throws when macOS refuses the request — most commonly because the
    /// app is being run straight out of Xcode's build folder rather than from
    /// `/Applications`. The caller surfaces the message to the user.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }
}
