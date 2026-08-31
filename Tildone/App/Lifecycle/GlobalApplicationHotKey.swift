//
//  GlobalApplicationHotKey.swift
//  Tildone
//

import AppKit
import Carbon.HIToolbox
import Combine

/// Registers a configurable application command shortcut with macOS.
@MainActor
final class GlobalApplicationHotKey: ObservableObject {
    static let lineUp = GlobalApplicationHotKey(action: .lineUp)
    static let newNote = GlobalApplicationHotKey(action: .newNote)

    @Published private(set) var hasConflict = false

    private enum Action {
        case lineUp
        case newNote

        var keyStorageKey: String {
            switch self {
            case .lineUp: AppShortcuts.lineUpKeyStorageKey
            case .newNote: AppShortcuts.newNoteKeyStorageKey
            }
        }

        var keyCodeStorageKey: String {
            switch self {
            case .lineUp: AppShortcuts.lineUpKeyCodeStorageKey
            case .newNote: AppShortcuts.newNoteKeyCodeStorageKey
            }
        }

        var modifiersStorageKey: String {
            switch self {
            case .lineUp: AppShortcuts.lineUpModifiersStorageKey
            case .newNote: AppShortcuts.newNoteModifiersStorageKey
            }
        }

        var defaultShortcut: MacAppShortcut {
            switch self {
            case .lineUp: AppShortcuts.defaultLineUp
            case .newNote: AppShortcuts.defaultNewNote
            }
        }

        var signature: OSType {
            switch self {
            case .lineUp: 0x54444C55 // "TDLU"
            case .newNote: 0x54444E4E // "TDNN"
            }
        }

        var notification: Notification.Name {
            switch self {
            case .lineUp: .arrange
            case .newNote: .new
            }
        }
    }

    private static let hotKeyIdentifier: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    private let action: Action
    private var hotKey: EventHotKeyRef?
    private var defaultsObserver: NSObjectProtocol?
    private var registeredShortcut: MacAppShortcut?

    private init(action: Action) {
        self.action = action
    }

    func start() {
        installEventHandlerIfNeeded()
        observeShortcutChangesIfNeeded()
        registerCurrentShortcut()
    }

    private func installEventHandlerIfNeeded() {
        guard Self.eventHandler == nil else { return }

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
            &Self.eventHandler
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
        let shortcut = AppShortcuts.shortcut(
            key: UserDefaults.standard.string(forKey: action.keyStorageKey)
                ?? action.defaultShortcut.key
                ?? "n",
            keyCodeRawValue: UserDefaults.standard.integer(forKey: action.keyCodeStorageKey),
            modifiersRawValue: UserDefaults.standard.integer(forKey: action.modifiersStorageKey),
            defaultShortcut: action.defaultShortcut
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
            EventHotKeyID(signature: action.signature, id: Self.hotKeyIdentifier),
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
              hotKeyID.id == GlobalApplicationHotKey.hotKeyIdentifier else {
            return noErr
        }

        let command: (notification: Notification.Name, activatesApplication: Bool)?
        switch hotKeyID.signature {
        case Action.lineUp.signature:
            command = (.arrange, false)
        case Action.newNote.signature:
            command = (.new, true)
        default:
            command = nil
        }
        guard let command else { return noErr }

        DispatchQueue.main.async {
            if command.activatesApplication {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            NotificationCenter.default.post(name: command.notification, object: nil)
        }
        return noErr
    }
}
