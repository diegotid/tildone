//
//  GlobalLineUpHotKey.swift
//  Tildone
//

import AppKit
import Carbon.HIToolbox
import Combine

/// Registers the configurable Line Up shortcut with macOS while Tildone is inactive.
@MainActor
final class GlobalLineUpHotKey: ObservableObject {
    static let shared = GlobalLineUpHotKey()

    @Published private(set) var hasConflict = false

    private static let hotKeySignature: OSType = 0x54444C55 // "TDLU"
    private static let hotKeyIdentifier: UInt32 = 1

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?
    private var registeredShortcut: MacAppShortcut?

    private init() {}

    func start() {
        installEventHandlerIfNeeded()
        observeShortcutChangesIfNeeded()
        registerCurrentShortcut()
    }

    func stop() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        registeredShortcut = nil
        hasConflict = false
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandlerCallback,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        assert(status == noErr, "Unable to install the global shortcut event handler.")
    }

    private func observeShortcutChangesIfNeeded() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.registerCurrentShortcut()
            }
        }
    }

    private func registerCurrentShortcut() {
        let shortcut = AppShortcuts.lineUp(
            key: UserDefaults.standard.string(forKey: AppShortcuts.lineUpKeyStorageKey)
                ?? AppShortcuts.defaultLineUp.key
                ?? "l",
            keyCodeRawValue: UserDefaults.standard.integer(forKey: AppShortcuts.lineUpKeyCodeStorageKey),
            modifiersRawValue: UserDefaults.standard.integer(forKey: AppShortcuts.lineUpModifiersStorageKey)
        )
        guard shortcut != registeredShortcut || hotKey == nil else { return }

        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }

        guard let keyCode = shortcut.keyCode else {
            hasConflict = true
            registeredShortcut = shortcut
            return
        }

        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers(for: shortcut.modifiers),
            EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIdentifier),
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )
        hotKey = registeredHotKey
        registeredShortcut = shortcut
        hasConflict = status != noErr
    }

    private func carbonModifiers(for modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static let eventHandlerCallback: EventHandlerUPP = { _, event, _ in
        guard let event else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == GlobalLineUpHotKey.hotKeySignature,
              hotKeyID.id == GlobalLineUpHotKey.hotKeyIdentifier else {
            return noErr
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .arrange, object: nil)
        }
        return noErr
    }
}
