//
//  KeyboardShortcutsHelp.swift
//  Tildone
//

import AppKit
import SwiftUI

struct KeyboardShortcutsHelp: View {
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AppShortcuts.opacityModifiersStorageKey)
    private var opacityModifiersRawValue = Int(AppShortcuts.defaultOpacity.modifiers.rawValue)
    @AppStorage(AppShortcuts.gatherModifiersStorageKey)
    private var gatherModifiersRawValue = Int(AppShortcuts.defaultGather.modifiers.rawValue)
    @AppStorage(AppShortcuts.lineUpKeyStorageKey)
    private var lineUpKey = AppShortcuts.defaultLineUp.key!
    @AppStorage(AppShortcuts.lineUpKeyCodeStorageKey)
    private var lineUpKeyCode = Int(AppShortcuts.defaultLineUp.keyCode ?? 0)
    @AppStorage(AppShortcuts.lineUpModifiersStorageKey)
    private var lineUpModifiersRawValue = Int(AppShortcuts.defaultLineUp.modifiers.rawValue)
    @AppStorage(AppShortcuts.newNoteKeyStorageKey)
    private var newNoteKey = AppShortcuts.defaultNewNote.key!
    @AppStorage(AppShortcuts.newNoteKeyCodeStorageKey)
    private var newNoteKeyCode = Int(AppShortcuts.defaultNewNote.keyCode ?? 0)
    @AppStorage(AppShortcuts.newNoteModifiersStorageKey)
    private var newNoteModifiersRawValue = Int(AppShortcuts.defaultNewNote.modifiers.rawValue)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
                    .font(.title2.bold())
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
            }
            Text("A quick reference for Tildone commands and gestures. Customizable shortcuts reflect your current Settings.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                section("Essentials") {
                    row("New Note", shortcut: newNoteShortcut.displayName)
                    row("Close Note", shortcut: "⌘W")
                    row("Undo", shortcut: "⌘Z")
                    row("Copy Note Contents", shortcut: "⇧⌘C")
                    row("Settings…", shortcut: "⌘,")
                }

                Divider()

                section("Window Management") {
                    row("Line Up Notes", shortcut: lineUpShortcut.displayName)
                    row("Minimize All", shortcut: "⇧⌘M")
                    row("Bring All Up", shortcut: "⇧⌘U")
                }

                Divider()

                section("Gestures") {
                    row("Dim or Restore Note", shortcut: scrollGesture(opacityShortcut))
                    row("Dim or Restore All Notes", shortcut: scrollGesture(opacityShortcut, addsShift: true))
                    row("Gather Notes", shortcut: scrollGesture(gatherShortcut))
                }

                Divider()

                section("Help") {
                    row("Keyboard Shortcuts", shortcut: "⌘/")
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var opacityShortcut: MacAppShortcut {
        AppShortcuts.opacity(from: opacityModifiersRawValue)
    }

    private var gatherShortcut: MacAppShortcut {
        AppShortcuts.gather(from: gatherModifiersRawValue)
    }

    private var lineUpShortcut: MacAppShortcut {
        AppShortcuts.lineUp(
            key: lineUpKey,
            keyCodeRawValue: lineUpKeyCode,
            modifiersRawValue: lineUpModifiersRawValue
        )
    }

    private var newNoteShortcut: MacAppShortcut {
        AppShortcuts.newNote(
            key: newNoteKey,
            keyCodeRawValue: newNoteKeyCode,
            modifiersRawValue: newNoteModifiersRawValue
        )
    }

    private func scrollGesture(_ shortcut: MacAppShortcut, addsShift: Bool = false) -> String {
        var modifiers = shortcut.modifiers
        if addsShift { modifiers.insert(.shift) }
        let keys = MacAppShortcut(key: nil, keyCode: nil, modifiers: modifiers).displayName
        return keys + " + " + String(localized: "Scroll")
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func row(_ title: LocalizedStringKey, shortcut: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer(minLength: 24)
            Text(verbatim: shortcut)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(shortcut.map(String.init).joined(separator: " "))
        }
    }
}
