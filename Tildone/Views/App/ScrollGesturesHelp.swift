//
//  ScrollGesturesHelp.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

struct ScrollGesturesHelp: View {
    @Environment(\.openSettings) private var openSettings
    @AppStorage(NoteColor.storageKey)
    private var noteColorRawValue = NoteColor.yellow.legacyRawValue
    @AppStorage(NoteWindowBackground.opacityStorageKey)
    private var noteBackgroundOpacity = Double(NoteWindowBackground.defaultAlpha)
    @AppStorage(FontSize.storageKey)
    private var fontSize = Double(FontSize.small.rawValue)
    @AppStorage(TaskLineTruncation.storageKey)
    private var taskLineTruncation: TaskLineTruncation = .single
    @AppStorage(ArrangementCorner.storageKey)
    private var selectedArrangementCorner: ArrangementCorner = .bottomLeft
    @AppStorage(ArrangementSpacing.cornerStorageKey)
    private var selectedArrangementCornerMargin: ArrangementSpacing = .medium
    @AppStorage(AppShortcuts.opacityModifiersStorageKey)
    private var opacityModifiersRawValue = Int(AppShortcuts.defaultOpacity.modifiers.rawValue)
    @AppStorage(AppShortcuts.gatherModifiersStorageKey)
    private var gatherModifiersRawValue = Int(AppShortcuts.defaultGather.modifiers.rawValue)

    private var noteColor: NoteColor {
        NoteColor(legacyRawValue: noteColorRawValue) ?? .yellow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Scroll Gestures", systemImage: "computermouse")
                    .font(.title2.bold())
                Spacer()
                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
            }
            Text("Use a mouse wheel or trackpad scroll gesture to dim notes or bring them together without interrupting your work.")
                .foregroundStyle(.secondary)

            gestureSection(
                title: "Note Dimming",
                shortcut: opacityShortcut
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Hold the shortcut while the pointer is over a note. Scroll down to dim it; scroll up to restore it.")
                    Text("Add Shift to apply the dimming change to all notes. Shift cannot be part of the shortcut itself.")
                }
            } preview: {
                DimmingPreview(
                    noteColor: noteColor,
                    backgroundOpacity: noteBackgroundOpacity,
                    fontSize: fontSize,
                    taskLineTruncation: taskLineTruncation
                )
            }

            Divider()

            gestureSection(
                title: "Gather Notes",
                shortcut: gatherShortcut
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Hold the shortcut and scroll over a note to gather all notes. Scroll up to restore their positions.")
                    Text("The corner selected for Line Up is also the Gather destination.")
                }
            } preview: {
                GatherPreview(
                    corner: selectedArrangementCorner,
                    margin: selectedArrangementCornerMargin,
                    noteColor: noteColor,
                    backgroundOpacity: noteBackgroundOpacity
                )
            }
        }
        .padding(24)
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var opacityShortcut: MacAppShortcut {
        AppShortcuts.opacity(from: opacityModifiersRawValue)
    }

    private var gatherShortcut: MacAppShortcut {
        AppShortcuts.gather(from: gatherModifiersRawValue)
    }

    private func gestureSection<Description: View, Preview: View>(
        title: LocalizedStringKey,
        shortcut: MacAppShortcut,
        @ViewBuilder description: () -> Description,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text("Current shortcut")
                        .foregroundStyle(.secondary)
                    shortcutBadge(shortcut)
                }
                description()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            preview()
        }
    }

    private func shortcutBadge(_ shortcut: MacAppShortcut) -> some View {
        Text(verbatim: shortcut.displayName + " + " + String(localized: "Scroll"))
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}
