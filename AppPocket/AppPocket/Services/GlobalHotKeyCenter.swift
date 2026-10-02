//
//  GlobalHotKeyCenter.swift
//  AppPocket
//
//  A system-wide hot key that shows and hides the launcher.
//

import AppKit
import Carbon.HIToolbox

/// The Carbon pieces, kept in one `nonisolated` namespace so the C callback has
/// a stable home and does not pick up the project's default main-actor isolation.
nonisolated enum GlobalHotKeyCarbon {
    /// `'APKT'`
    static let signature: OSType = 0x4150_4B54

    /// A C function pointer, so it captures nothing and dereferences the centre
    /// through the user-data pointer instead.
    static let eventHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
        // Carbon dispatches hot key events on the main run loop.
        MainActor.assumeIsolated {
            center.fire()
        }
        return noErr
    }
}

@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    var isRegistered: Bool { hotKeyRef != nil }

    /// Registers `spec`, replacing any previous registration.
    /// - Returns: `true` when the system accepted the hot key.
    @discardableResult
    func register(_ spec: HotKeySpec, action: @escaping () -> Void) -> Bool {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            GlobalHotKeyCarbon.eventHandler,
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard installStatus == noErr else {
            NSLog("[AppPocket] InstallEventHandler failed: %d", installStatus)
            self.action = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: GlobalHotKeyCarbon.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            NSLog("[AppPocket] RegisterEventHotKey failed: %d (the combination may be taken)", registerStatus)
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef {
            _ = UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            _ = RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        action = nil
    }

    fileprivate func fire() {
        action?()
    }
}
