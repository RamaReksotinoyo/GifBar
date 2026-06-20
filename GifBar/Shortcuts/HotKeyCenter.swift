//
//  HotKeyCenter.swift
//  GifBar
//
//  Iteration 7c — Global shortcut (SPEC §6).
//
//  Registers a system-wide ⌘⇧5 hotkey so a recording can be stopped without
//  bringing GifBar forward. Uses Carbon's `RegisterEventHotKey`, which works
//  under the App Sandbox and needs no Accessibility permission — unlike
//  `NSEvent.addGlobalMonitorForEvents`.
//

import AppKit
import Carbon

/// Owns a single global hotkey and reports presses via ``onTrigger``.
///
/// One of the few reference types allowed by SPEC §3: a Carbon coordinator whose
/// C event handler must outlive any value-typed view.
@MainActor
final class HotKeyCenter {
    /// Virtual key code for the "5" key (⌘⇧5).
    static let keyCode = UInt32(kVK_ANSI_5)

    /// Command + Shift, as Carbon modifier flags.
    static let modifiers = UInt32(cmdKey | shiftKey)

    /// Four-char signature identifying this app's hotkeys.
    private static let signature: OSType = 0x4749_4642 // 'GIFB'

    /// Called on the main thread each time the hotkey is pressed.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    /// Installs the event handler and registers ⌘⇧5. Safe to call once at launch.
    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon's callback is a C function pointer that cannot capture context,
        // so `self` is threaded through `userData` and recovered inside it.
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // Hotkey events are delivered on the main run loop.
            MainActor.assumeIsolated { center.onTrigger?() }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    nonisolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
