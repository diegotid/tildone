//
//  Settings.swift
//  Tildone
//
//  Created by Diego Rivera on 6/1/24.
//

import SwiftUI
import AppKit
import TildoneDomain

// MARK: Configurable shortcuts

struct MacAppShortcut: Equatable {
    static let significantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var key: String?
    /// The physical key recorded by AppKit, used for global shortcut registration.
    /// Older preferences do not have this value and fall back to `AppShortcuts.keyCode(for:)`.
    var keyCode: UInt16?
    var modifiers: NSEvent.ModifierFlags

    var displayName: String {
        let modifierNames = [
            (NSEvent.ModifierFlags.control, "⌃"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘")
        ]
        let prefix = modifierNames.compactMap { modifiers.contains($0.0) ? $0.1 : nil }.joined()
        return prefix + (key?.uppercased() ?? "")
    }

    func matches(_ eventModifiers: NSEvent.ModifierFlags) -> Bool {
        eventModifiers.intersection(Self.significantModifiers) == modifiers
    }
}

enum AppShortcuts {
    static let opacityModifiersStorageKey = "noteOpacityWheelShortcutModifiers"
    static let gatherModifiersStorageKey = "noteGatherWheelShortcutModifiers"
    static let lineUpKeyStorageKey = "lineUpNotesShortcutKey"
    static let lineUpKeyCodeStorageKey = "lineUpNotesShortcutKeyCode"
    static let lineUpModifiersStorageKey = "lineUpNotesShortcutModifiers"
    static let newNoteKeyStorageKey = "newNoteShortcutKey"
    static let newNoteKeyCodeStorageKey = "newNoteShortcutKeyCode"
    static let newNoteModifiersStorageKey = "newNoteShortcutModifiers"

    static let defaultOpacity = MacAppShortcut(key: nil, keyCode: nil, modifiers: [.option])
    static let defaultGather = MacAppShortcut(key: nil, keyCode: nil, modifiers: [.option, .control])
    static let defaultLineUp = MacAppShortcut(key: "l", keyCode: 37, modifiers: [.command, .shift])
    static let defaultNewNote = MacAppShortcut(key: "t", keyCode: 17, modifiers: [.command, .shift])

    static func opacity(from rawValue: Int) -> MacAppShortcut {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawValue))
            .intersection(MacAppShortcut.significantModifiers)
            .subtracting(.shift)
        return modifiers.isEmpty || modifiers == [.command]
            ? defaultOpacity
            : MacAppShortcut(key: nil, keyCode: nil, modifiers: modifiers)
    }

    static func opacityShortcut(
        _ shortcut: MacAppShortcut,
        matches eventModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let modifiersWithoutShift = eventModifiers
            .intersection(MacAppShortcut.significantModifiers)
            .subtracting(.shift)
        return modifiersWithoutShift == shortcut.modifiers
    }

    static func gather(from rawValue: Int) -> MacAppShortcut {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(rawValue))
            .intersection(MacAppShortcut.significantModifiers)
        return modifiers.isEmpty || modifiers == [.command, .control]
            ? defaultGather
            : MacAppShortcut(key: nil, keyCode: nil, modifiers: modifiers)
    }

    static func lineUp(
        key: String,
        keyCodeRawValue: Int = 0,
        modifiersRawValue: Int
    ) -> MacAppShortcut {
        shortcut(
            key: key,
            keyCodeRawValue: keyCodeRawValue,
            modifiersRawValue: modifiersRawValue,
            defaultShortcut: defaultLineUp
        )
    }

    static func newNote(
        key: String,
        keyCodeRawValue: Int = 0,
        modifiersRawValue: Int
    ) -> MacAppShortcut {
        shortcut(
            key: key,
            keyCodeRawValue: keyCodeRawValue,
            modifiersRawValue: modifiersRawValue,
            defaultShortcut: defaultNewNote
        )
    }

    static func shortcut(
        key: String,
        keyCodeRawValue: Int = 0,
        modifiersRawValue: Int,
        defaultShortcut: MacAppShortcut
    ) -> MacAppShortcut {
        let normalizedKey = key.first.map { String($0).lowercased() } ?? defaultShortcut.key!
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRawValue))
            .intersection(MacAppShortcut.significantModifiers)
        return MacAppShortcut(
            key: normalizedKey,
            keyCode: keyCodeRawValue > 0
                ? UInt16(keyCodeRawValue)
                : keyCode(for: normalizedKey),
            modifiers: modifiers.isEmpty ? defaultShortcut.modifiers : modifiers
        )
    }

    static func keyCode(for key: String?) -> UInt16? {
        guard let character = key?.lowercased().first else { return nil }
        return ansiKeyCodes[character]
    }

    private static let ansiKeyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50
    ]
}

// MARK: Settings view

private enum SettingsTab: Hashable {
    case general
    case appearance
    case positioning
}

struct SettingsForm: View {
    private static let windowWidth: CGFloat = 600

    @State private var selectedTab: SettingsTab = .general
    @State private var opacityShortcutValidationMessage: LocalizedStringKey?
    @State private var gatherShortcutValidationMessage: LocalizedStringKey?
    @State private var lineUpShortcutValidationMessage: LocalizedStringKey?
    @State private var newNoteShortcutValidationMessage: LocalizedStringKey?
    @ObservedObject private var globalLineUpHotKey = GlobalApplicationHotKey.lineUp
    @ObservedObject private var globalNewNoteHotKey = GlobalApplicationHotKey.newNote
    
    @AppStorage(FontSize.storageKey)
    private var fontSize = Double(FontSize.small.rawValue)
    
    @AppStorage(TaskLineTruncation.storageKey)
    private var taskLineTruncation: TaskLineTruncation = .single
    
    @AppStorage(ArrangementCorner.storageKey)
    private var selectedArrangementCorner: ArrangementCorner = .bottomLeft
    
    @AppStorage(ArrangementAlignment.storageKey)
    private var selectedArrangementAlignment: ArrangementAlignment = .horizontal
    
    @AppStorage(ArrangementSpacing.cornerStorageKey)
    private var selectedArrangementCornerMargin: ArrangementSpacing = .medium
    
    @AppStorage(ArrangementSpacing.sideStorageKey)
    private var selectedArrangementSpacing: ArrangementSpacing = .minimum
    
    @AppStorage(NoteColor.storageKey)
    private var noteColorRawValue = NoteColor.yellow.legacyRawValue

    private var noteColor: NoteColor {
        NoteColor(legacyRawValue: noteColorRawValue) ?? .yellow
    }
    
    @AppStorage(NoteWindowBackground.opacityStorageKey)
    private var noteBackgroundOpacity = Double(NoteWindowBackground.defaultAlpha)

    @AppStorage(AppAppearance.showDockIconStorageKey)
    private var showDockIcon = false

    @AppStorage(AppAppearance.moveCheckedTasksToEndStorageKey)
    private var moveCheckedTasksToEnd = false

    @AppStorage(NoteWindowClickThrough.storageKey)
    private var clickThroughNotes = false

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
        TabView(selection: $selectedTab) {
            settingsPane { generalSettings() }
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            settingsPane { appearanceSettings() }
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
            settingsPane { positioningSettings() }
                .tabItem { Label("Positioning", systemImage: "rectangle.3.group") }
                .tag(SettingsTab.positioning)
        }
        .frame(width: Self.windowWidth, height: preferredWindowHeight)
        .animation(.easeInOut(duration: 0.18), value: preferredWindowHeight)
        .onAppear(perform: enforceClickThroughAvailability)
        .onChange(of: noteBackgroundOpacity) { _, _ in
            enforceClickThroughAvailability()
        }
    }

    private var preferredWindowHeight: CGFloat {
        let paneHeight: CGFloat
        switch selectedTab {
        case .general: paneHeight = 188
        case .appearance: paneHeight = 504
        case .positioning: paneHeight = 474
        }
        return Self.preferredWindowHeight(
            contentHeight: paneHeight,
            width: Self.windowWidth
        )
    }
}

// MARK: Form components

private extension SettingsForm {
    @ViewBuilder
    func settingsPane<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func generalSettings() -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                settingWithHelp("Start Tildone automatically when you log in.") {
                    Launcher.Toggle()
                }
                settingWithHelp("Show or hide Tildone in the Dock.") {
                    Toggle("Show Dock icon", isOn: $showDockIcon)
                        .onChange(of: showDockIcon) { _, _ in
                            NSApplication.shared.setActivationPolicy(showDockIcon ? .regular : .accessory)
                        }
                }
                settingWithHelp("Keep unfinished tasks at the top of each list.") {
                    Toggle("Move checked tasks to the end", isOn: $moveCheckedTasksToEnd)
                        .onChange(of: moveCheckedTasksToEnd) { _, isEnabled in
                            NotificationCenter.default.post(
                                name: .updateCompletedTaskOrdering,
                                object: isEnabled
                            )
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Text("New Note")
                    .font(.headline)
                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorder(
                        shortcut: newNoteShortcutBinding,
                        kind: .key,
                        validationMessage: $newNoteShortcutValidationMessage
                    )
                }
                shortcutValidationMessage(newNoteShortcutValidationMessage)
                if globalNewNoteHotKey.hasConflict {
                    globalShortcutConflictWarning
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func appearanceSettings() -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                noteColorSettings()
                fontSizeSettings()
                taskWrappingSettings()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 24) {
                staticAppearancePreview()
                    .padding(.top, 12)
                clickThroughSetting()
            }
        }

        Divider()

        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Note dimming:")
                    .font(.headline)
                LabeledContent("Scroll shortcut") {
                    ShortcutRecorder(
                        shortcut: opacityShortcutBinding,
                        kind: .modifiers(disallowsShift: true, disallowsCommand: true),
                        validationMessage: $opacityShortcutValidationMessage
                    )
                }
                shortcutValidationMessage(opacityShortcutValidationMessage)
                Text("Hold this shortcut and scroll over a note to dim or restore its entire window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Add Shift to apply the dimming change to all notes. Shift cannot be part of the shortcut itself.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            dimmingPreview()
        }
    }

    @ViewBuilder
    func positioningSettings() -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Line Up:")
                    .font(.headline)
                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorder(
                        shortcut: lineUpShortcutBinding,
                        kind: .key,
                        validationMessage: $lineUpShortcutValidationMessage
                    )
                }
                shortcutValidationMessage(lineUpShortcutValidationMessage)
                if globalLineUpHotKey.hasConflict {
                    globalShortcutConflictWarning
                }
                Text("Place notes in an evenly spaced row or column.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Corner")
                        .frame(width: 120, alignment: .leading)
                    Spacer(minLength: 16)
                    Picker("", selection: $selectedArrangementCorner) {
                        Text("Bottom left").tag(ArrangementCorner.bottomLeft)
                        Text("Bottom right").tag(ArrangementCorner.bottomRight)
                        Text("Top right").tag(ArrangementCorner.topRight)
                        Text("Top left").tag(ArrangementCorner.topLeft)
                    }
                    .labelsHidden()
                }
                HStack {
                    Text("Margin")
                        .frame(width: 120, alignment: .leading)
                    Spacer(minLength: 16)
                    Picker("", selection: $selectedArrangementCornerMargin) {
                        Text("Minimum").tag(ArrangementSpacing.minimum)
                        Text("Medium").tag(ArrangementSpacing.medium)
                        Text("Maximum").tag(ArrangementSpacing.maximum)
                    }
                    .labelsHidden()
                }
                HStack {
                    Text("Direction")
                        .frame(width: 120, alignment: .leading)
                    Spacer(minLength: 16)
                    Picker("", selection: $selectedArrangementAlignment) {
                        Text("Horizontal").tag(ArrangementAlignment.horizontal)
                        Text("Vertical").tag(ArrangementAlignment.vertical)
                    }
                    .labelsHidden()
                }
                HStack {
                    Text("Spacing")
                        .frame(width: 120, alignment: .leading)
                    Spacer(minLength: 16)
                    Picker("", selection: $selectedArrangementSpacing) {
                        Text("Minimum").tag(ArrangementSpacing.minimum)
                        Text("Medium").tag(ArrangementSpacing.medium)
                        Text("Maximum").tag(ArrangementSpacing.maximum)
                    }
                    .labelsHidden()
                }
            }
            LineUpPreview(
                corner: selectedArrangementCorner,
                margin: selectedArrangementCornerMargin,
                alignment: selectedArrangementAlignment,
                spacing: selectedArrangementSpacing,
                noteColor: noteColor,
                backgroundOpacity: noteBackgroundOpacity,
                shortcut: lineUpShortcutBinding.wrappedValue
            )
        }

        Divider()

        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Gather:")
                    .font(.headline)
                Text("Hold the shortcut and scroll over a note to gather all notes. Scroll up to restore their positions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The corner selected for Line Up is also the Gather destination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Scroll shortcut") {
                    ShortcutRecorder(
                        shortcut: gatherShortcutBinding,
                        kind: .modifiers(disallowsShift: false, disallowsCommand: true),
                        validationMessage: $gatherShortcutValidationMessage
                    )
                }
                shortcutValidationMessage(gatherShortcutValidationMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GatherPreview(
                corner: selectedArrangementCorner,
                margin: selectedArrangementCornerMargin,
                noteColor: noteColor,
                backgroundOpacity: noteBackgroundOpacity
            )
        }
    }

    @ViewBuilder
    func settingWithHelp<Content: View>(_ help: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func shortcutValidationMessage(_ message: LocalizedStringKey?) -> some View {
        if let message {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
    
    @ViewBuilder
    func fontSizeSettings() -> some View {
        Text("Font size")
            .foregroundColor(.secondary)
            .padding(.top, 3)
        Slider(
            value: fontSizeBinding,
            in: Double(FontSize.xSmall.rawValue)...Double(FontSize.xLarge.rawValue)
        ) {
            Text("Font size")
        }
        .labelsHidden()
        .frame(width: FontSizeSliderLayout.width)
        .overlay(alignment: .leading) {
            SliderTrackMarker(
                markX: FontSizeSliderLayout.defaultMarkX,
                thumbX: SettingsSliderLayout.markX(
                    for: fontSizeBinding.wrappedValue,
                    in: Double(FontSize.xSmall.rawValue)...Double(FontSize.xLarge.rawValue)
                )
            )
        }
    }
    
    @ViewBuilder
    func taskWrappingSettings() -> some View {
        Text("Task wrapping")
            .foregroundColor(.secondary)
            .padding(.top, 3)
        Picker("", selection: $taskLineTruncation) {
            SettingsForm.taskAppearanceText(with: .single)
                .tag(TaskLineTruncation.single)
            SettingsForm.taskAppearanceText(with: .multiple)
                .tag(TaskLineTruncation.multiple)
        }
        .pickerStyle(.radioGroup)
        .padding(.vertical, 1)
    }
    
    @ViewBuilder
    func noteColorSettings() -> some View {
        Text("Default note color")
            .foregroundColor(.secondary)
            .padding(.top, 8)
        HStack(spacing: 9) {
            ForEach(NoteColor.allCases) { option in
                noteColorSample(for: option)
            }
        }
        Text("Note background transparency")
            .foregroundColor(.secondary)
            .padding(.top, 8)
        Slider(value: noteBackgroundTransparencyBinding, in: 0...1) {
            Text("Note background transparency")
        }
        .labelsHidden()
        .frame(width: TransparencySliderLayout.width)
        .overlay(alignment: .leading) {
            SliderTrackMarker(
                markX: TransparencySliderLayout.thresholdMarkX,
                thumbX: SettingsSliderLayout.markX(
                    for: noteBackgroundTransparencyBinding.wrappedValue,
                    in: 0...1
                )
            )
        }
    }

    @ViewBuilder
    func clickThroughSetting() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Click through notes", isOn: $clickThroughNotes)
                .disabled(!isClickThroughAvailable)
            Group {
                if isClickThroughAvailable {
                    Text("When enabled, hold ⌘ while clicking to interact with a transparent note.")
                } else {
                    Text(
                        "Requires at least \(NoteWindowClickThrough.minimumBackgroundTransparency, format: .percent.precision(.fractionLength(0))) note background transparency."
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 240, alignment: .leading)
    }
    
    @ViewBuilder
    func noteColorSample(for option: NoteColor) -> some View {
        let isSelected = noteColor == option
        RoundedRectangle(cornerRadius: 6)
            .fill(option.fillStyle)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear,
                            lineWidth: isSelected ? 5 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                noteColorRawValue = option.legacyRawValue
            }
            .help(option.localizedLabel)
    }
    
    @ViewBuilder
    func staticAppearancePreview() -> some View {
        appearancePreview(windowAlpha: 1, scrollGesture: nil)
    }

    @ViewBuilder
    func dimmingPreview() -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            appearancePreview(
                windowAlpha: SettingsForm.opacityPreviewValue(at: context.date),
                scrollGesture: SettingsForm.opacityChevronState(at: context.date)
            )
        }
    }

    @ViewBuilder
    func appearancePreview(windowAlpha: Double, scrollGesture: ScrollChevronState?) -> some View {
        SettingsPreviewCanvas {
            SampleSettingsNote(
                noteColor: noteColor,
                backgroundOpacity: noteBackgroundOpacity,
                fontSize: fontSize,
                taskLineTruncation: taskLineTruncation,
                showsContent: true
            )
            .frame(width: 190, height: 142)
            .opacity(windowAlpha)
            if let scrollGesture {
                ScrollChevronIndicator(state: scrollGesture)
                    .position(x: ScrollChevronLayout.previewCenterX, y: 80)
            }
        }
    }

    var noteBackgroundTransparencyBinding: Binding<Double> {
        Binding(
            get: { SettingsForm.backgroundTransparency(fromOpacity: noteBackgroundOpacity) },
            set: { newTransparency in
                let previousTransparency = SettingsForm.backgroundTransparency(
                    fromOpacity: noteBackgroundOpacity
                )
                if SettingsForm.crossesClickThroughThreshold(
                    from: previousTransparency,
                    to: newTransparency
                ) {
                    performSliderMarkerHaptic()
                }
                noteBackgroundOpacity = SettingsForm.backgroundOpacity(
                    fromTransparency: newTransparency
                )
            }
        )
    }

    var fontSizeBinding: Binding<Double> {
        Binding(
            get: { fontSize },
            set: { newFontSize in
                if SettingsForm.crossesFontSizeDefault(
                    from: fontSize,
                    to: newFontSize
                ) {
                    performSliderMarkerHaptic()
                }
                fontSize = newFontSize
            }
        )
    }

    func performSliderMarkerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .now
        )
    }

    var isClickThroughAvailable: Bool {
        NoteWindowClickThrough.isAvailable(
            backgroundTransparency: SettingsForm.backgroundTransparency(
                fromOpacity: noteBackgroundOpacity
            )
        )
    }

    func enforceClickThroughAvailability() {
        if !isClickThroughAvailable {
            clickThroughNotes = false
        }
    }

    var opacityShortcutBinding: Binding<MacAppShortcut> {
        Binding(
            get: { AppShortcuts.opacity(from: opacityModifiersRawValue) },
            set: { opacityModifiersRawValue = Int($0.modifiers.rawValue) }
        )
    }

    var gatherShortcutBinding: Binding<MacAppShortcut> {
        Binding(
            get: { AppShortcuts.gather(from: gatherModifiersRawValue) },
            set: { gatherModifiersRawValue = Int($0.modifiers.rawValue) }
        )
    }

    var lineUpShortcutBinding: Binding<MacAppShortcut> {
        Binding(
            get: {
                AppShortcuts.lineUp(
                    key: lineUpKey,
                    keyCodeRawValue: lineUpKeyCode,
                    modifiersRawValue: lineUpModifiersRawValue
                )
            },
            set: {
                lineUpKey = $0.key ?? AppShortcuts.defaultLineUp.key!
                lineUpKeyCode = Int($0.keyCode ?? AppShortcuts.keyCode(for: $0.key) ?? 0)
                lineUpModifiersRawValue = Int($0.modifiers.rawValue)
            }
        )
    }

    var newNoteShortcutBinding: Binding<MacAppShortcut> {
        Binding(
            get: {
                AppShortcuts.newNote(
                    key: newNoteKey,
                    keyCodeRawValue: newNoteKeyCode,
                    modifiersRawValue: newNoteModifiersRawValue
                )
            },
            set: {
                newNoteKey = $0.key ?? AppShortcuts.defaultNewNote.key!
                newNoteKeyCode = Int($0.keyCode ?? AppShortcuts.keyCode(for: $0.key) ?? 0)
                newNoteModifiersRawValue = Int($0.modifiers.rawValue)
            }
        )
    }

    var globalShortcutConflictWarning: some View {
        Label(
            "This shortcut is used by another app. Choose another shortcut to make it work globally.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }
}

private struct SettingsPreviewCanvas<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            SettingsPreviewBackground()
            content
        }
        .frame(width: 240, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

enum TransparencySliderLayout {
    static let width = SettingsSliderLayout.width
    static let thresholdMarkX = SettingsSliderLayout.markX(
        for: NoteWindowClickThrough.minimumBackgroundTransparency,
        in: 0...1
    )
}

enum FontSizeSliderLayout {
    static let width = SettingsSliderLayout.width
    static let defaultMarkX = SettingsSliderLayout.markX(
        for: Double(FontSize.small.rawValue),
        in: Double(FontSize.xSmall.rawValue)...Double(FontSize.xLarge.rawValue)
    )
}

private enum SettingsSliderLayout {
    static let width: CGFloat = 200
    private static let thumbInset: CGFloat = 8

    static func markX(for value: Double, in range: ClosedRange<Double>) -> CGFloat {
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return thumbInset + (width - 2 * thumbInset) * progress
    }
}

private struct SliderTrackMarker: View {
    let markX: CGFloat
    let thumbX: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.secondary.opacity(0.65))
                .frame(width: 1, height: 8)
                .offset(x: markX - 0.5)

            Circle()
                .frame(width: 20, height: 20)
                .offset(x: thumbX - 10)
                .blendMode(.destinationOut)
        }
        .frame(width: SettingsSliderLayout.width, height: 20, alignment: .leading)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SettingsPreviewBackground: View {
    var body: some View {
        Image("desktop")
            .resizable()
            .scaledToFill()
            .frame(width: 240, height: 160)
            .clipped()
    }
}

private struct SampleSettingsNote: View {
    let noteColor: NoteColor
    let backgroundOpacity: Double
    let fontSize: Double
    let taskLineTruncation: TaskLineTruncation
    let showsContent: Bool
    var cornerRadius: CGFloat = 10

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VisualEffectBlurView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: noteColor.nsColor).opacity(backgroundOpacity))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 3)
            if showsContent {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            Circle()
                                .frame(width: 8, height: 8)
                                .foregroundStyle(index == 1 ? Color.yellow : .gray.opacity(0.4))
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 10)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Weekend plans")
                            .font(.system(size: CGFloat(fontSize) + 1, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        sampleTask("Book a table", isDone: true)
                        sampleTask("Pick up fresh flowers", isDone: false)
                        sampleTask("Choose a longer scenic route home", isDone: false)
                    }
                    .font(.system(size: CGFloat(fontSize)))
                    .foregroundStyle(
                        NoteContentForeground.color(
                            colorScheme: colorScheme,
                            backgroundOpacity: backgroundOpacity
                        )
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 7)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func sampleTask(_ title: LocalizedStringKey, isDone: Bool) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Checkbox(checked: isDone)
                .padding(.top, max(0, CGFloat(fontSize) - Layout.checkboxSize) / 2)
            Text(title)
                .strikethrough(isDone)
                .lineLimit(taskLineTruncation == .single ? 1 : 2)
        }
    }
}

struct ScrollChevronState: Equatable {
    let travelOffset: CGFloat
    let pointsDown: Bool
    let directionTransitionOpacity: Double
}

enum ScrollChevronLayout {
    static let count = 6
    static let travelSpan: CGFloat = 60
    static let indicatorWidth: CGFloat = 24
    static let previewCenterX: CGFloat = 228

    static func previewCenterX(for corner: ArrangementCorner) -> CGFloat {
        corner == .bottomRight ? 16 : previewCenterX
    }

    static func verticalOffset(for index: Int, travelOffset: CGFloat) -> CGFloat {
        let spacing = travelSpan / CGFloat(count)
        let centeredIndex = CGFloat(index) - CGFloat(count - 1) / 2
        let unwrapped = centeredIndex * spacing + travelOffset
        let halfSpan = travelSpan / 2
        var wrapped = (unwrapped + halfSpan).truncatingRemainder(dividingBy: travelSpan)
        if wrapped < 0 {
            wrapped += travelSpan
        }
        return wrapped - halfSpan
    }

    static func opacity(at verticalOffset: CGFloat) -> Double {
        let distanceFromCenter = abs(verticalOffset) / (travelSpan / 2)
        return Double(max(0, 1 - distanceFromCenter))
    }
}

private struct ScrollChevronIndicator: View {
    let state: ScrollChevronState

    var body: some View {
        ZStack {
            ForEach(0..<ScrollChevronLayout.count, id: \.self) { index in
                let verticalOffset = ScrollChevronLayout.verticalOffset(
                    for: index,
                    travelOffset: state.travelOffset
                )
                Image(systemName: state.pointsDown ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .offset(y: verticalOffset)
                    .opacity(ScrollChevronLayout.opacity(at: verticalOffset))
            }
        }
        .frame(
            width: ScrollChevronLayout.indicatorWidth,
            height: ScrollChevronLayout.travelSpan
        )
        .clipped()
        .opacity(state.directionTransitionOpacity)
        .accessibilityHidden(true)
    }
}

private struct LineUpPreview: View {
    let corner: ArrangementCorner
    let margin: ArrangementSpacing
    let alignment: ArrangementAlignment
    let spacing: ArrangementSpacing
    let noteColor: NoteColor
    let backgroundOpacity: Double
    let shortcut: MacAppShortcut

    @State private var progress: CGFloat = 0
    @State private var hasAnimated = false

    private let starts = [
        CGPoint(x: 42, y: 39),
        CGPoint(x: 121, y: 88),
        CGPoint(x: 193, y: 48)
    ]
    private let noteSize = CGSize(width: 24, height: 30)

    var body: some View {
        SettingsPreviewCanvas {
            ForEach(starts.indices, id: \.self) { index in
                let target = targetCenter(
                    for: LineUpPreviewLayout.position(
                        of: index,
                        in: starts,
                        alignment: alignment,
                        corner: corner
                    )
                )
                SampleSettingsNote(
                    noteColor: noteColor,
                    backgroundOpacity: backgroundOpacity,
                    fontSize: Double(FontSize.small.rawValue),
                    taskLineTruncation: .single,
                    showsContent: false,
                    cornerRadius: 3
                )
                .frame(width: noteSize.width, height: noteSize.height)
                .position(
                    x: starts[index].x + (target.x - starts[index].x) * progress,
                    y: starts[index].y + (target.y - starts[index].y) * progress
                )
            }
            VStack {
                Spacer()
                HStack {
                    if corner != .bottomRight {
                        Spacer()
                    }
                    Button(action: replay) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text(shortcut.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(.white.opacity(0.18))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Replay Line Up preview")
                    if corner == .bottomRight {
                        Spacer()
                    }
                }
            }
            .padding(8)
        }
        .onAppear {
            guard !hasAnimated else { return }
            hasAnimated = true
            replay()
        }
    }

    private func replay() {
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            progress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 1.4)) {
                progress = 1
            }
        }
    }

    private func targetCenter(for position: Int) -> CGPoint {
        let previewMargin = CGFloat(margin.rawValue) / 4
        let previewSpacing = CGFloat(spacing.rawValue) / 8
        let targetsRight = corner == .bottomRight || corner == .topRight
        let targetsTop = corner == .topLeft || corner == .topRight
        let stepX = noteSize.width + previewSpacing
        let stepY = noteSize.height + previewSpacing
        switch alignment {
        case .horizontal:
            return CGPoint(
                x: targetsRight
                    ? 240 - previewMargin - noteSize.width / 2 - CGFloat(position) * stepX
                    : previewMargin + noteSize.width / 2 + CGFloat(position) * stepX,
                y: targetsTop
                    ? previewMargin + noteSize.height / 2
                    : 160 - previewMargin - noteSize.height / 2
            )
        case .vertical:
            return CGPoint(
                x: targetsRight
                    ? 240 - previewMargin - noteSize.width / 2
                    : previewMargin + noteSize.width / 2,
                y: targetsTop
                    ? previewMargin + noteSize.height / 2 + CGFloat(position) * stepY
                    : 160 - previewMargin - noteSize.height / 2 - CGFloat(position) * stepY
            )
        }
    }
}

enum LineUpPreviewLayout {
    static func position(
        of index: Int,
        in starts: [CGPoint],
        alignment: ArrangementAlignment,
        corner: ArrangementCorner
    ) -> Int {
        orderedIndices(in: starts, alignment: alignment, corner: corner)
            .firstIndex(of: index) ?? index
    }

    static func orderedIndices(
        in starts: [CGPoint],
        alignment: ArrangementAlignment,
        corner: ArrangementCorner
    ) -> [Int] {
        let targetsRight = corner == .bottomRight || corner == .topRight
        let targetsTop = corner == .topLeft || corner == .topRight
        return starts.indices.sorted { lhs, rhs in
            switch alignment {
            case .horizontal:
                return targetsRight
                    ? starts[lhs].x > starts[rhs].x
                    : starts[lhs].x < starts[rhs].x
            case .vertical:
                // AppKit's screen Y-axis points up; this preview's Y-axis points down.
                return targetsTop
                    ? starts[lhs].y < starts[rhs].y
                    : starts[lhs].y > starts[rhs].y
            }
        }
    }
}

private struct GatherPreview: View {
    let corner: ArrangementCorner
    let margin: ArrangementSpacing
    let noteColor: NoteColor
    let backgroundOpacity: Double

    private let starts = [
        CGPoint(x: 36, y: 37),
        CGPoint(x: 119, y: 81),
        CGPoint(x: 193, y: 47)
    ]
    private let sizes = [
        CGSize(width: 27, height: 35),
        CGSize(width: 35, height: 45),
        CGSize(width: 23, height: 31)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let progress = SettingsForm.gatherPreviewProgress(at: context.date)
            SettingsPreviewCanvas {
                ForEach(starts.indices, id: \.self) { index in
                    let target = targetCenter(for: index)
                    SampleSettingsNote(
                        noteColor: noteColor,
                        backgroundOpacity: backgroundOpacity,
                        fontSize: Double(FontSize.small.rawValue),
                        taskLineTruncation: .single,
                        showsContent: false,
                        cornerRadius: 4
                    )
                    .frame(width: sizes[index].width, height: sizes[index].height)
                    .position(
                        x: starts[index].x + (target.x - starts[index].x) * progress,
                        y: starts[index].y + (target.y - starts[index].y) * progress
                    )
                    .zIndex(Double(sizes.count - index))
                }
                ScrollChevronIndicator(
                    state: SettingsForm.gatherChevronState(at: context.date)
                )
                .position(
                    x: ScrollChevronLayout.previewCenterX(for: corner),
                    y: 80
                )
            }
        }
    }

    private func targetCenter(for index: Int) -> CGPoint {
        let previewMargin = CGFloat(margin.rawValue) / 4
        let stagger = CGFloat(index) * 5
        let size = sizes[index]
        let targetsRight = corner == .bottomRight || corner == .topRight
        let targetsTop = corner == .topLeft || corner == .topRight
        return CGPoint(
            x: targetsRight
                ? 240 - previewMargin - size.width / 2 - stagger
                : previewMargin + size.width / 2 + stagger,
            y: targetsTop
                ? previewMargin + size.height / 2 + stagger
                : 160 - previewMargin - size.height / 2 - stagger
        )
    }
}

private enum ShortcutRecorderKind: Equatable {
    case key
    case modifiers(disallowsShift: Bool, disallowsCommand: Bool)
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: MacAppShortcut
    let kind: ShortcutRecorderKind
    @Binding var validationMessage: LocalizedStringKey?
    @State private var isRecording = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button {
                validationMessage = nil
                draft = ""
                isRecording = true
            } label: {
                Group {
                    if isRecording {
                        if draft.isEmpty {
                            Text("Type new")
                        } else {
                            Text(verbatim: draft)
                        }
                    } else {
                        Text(verbatim: shortcut.displayName)
                    }
                }
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .tracking(isRecording && draft.isEmpty ? 0 : 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: 56, height: 20)
            }
            .buttonStyle(.bordered)
            .background {
                ShortcutCaptureView(
                    isRecording: $isRecording,
                    kind: kind,
                    onDraft: { draft = $0.displayName },
                    onCommit: commit,
                    onValidationError: { validationMessage = $0 }
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
        }
    }

    private func commit(_ newShortcut: MacAppShortcut) {
        shortcut = newShortcut
        validationMessage = nil
        isRecording = false
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let kind: ShortcutRecorderKind
    let onDraft: (MacAppShortcut) -> Void
    let onCommit: (MacAppShortcut) -> Void
    let onValidationError: (LocalizedStringKey) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        configure(nsView)
        guard isRecording else { return }
        DispatchQueue.main.async {
            guard nsView.window?.makeFirstResponder(nsView) == true else {
                isRecording = false
                return
            }
        }
    }

    private func configure(_ view: ShortcutCaptureNSView) {
        view.isRecording = isRecording
        view.kind = kind
        view.onDraft = onDraft
        view.onCommit = onCommit
        view.onCancel = { isRecording = false }
        view.onValidationError = onValidationError
    }
}

private final class ShortcutCaptureNSView: NSView {
    var isRecording = false
    var kind: ShortcutRecorderKind = .key
    var onDraft: ((MacAppShortcut) -> Void)?
    var onCommit: ((MacAppShortcut) -> Void)?
    var onCancel: (() -> Void)?
    var onValidationError: ((LocalizedStringKey) -> Void)?
    private var pendingModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 {
            pendingModifiers = []
            onCancel?()
            return
        }
        guard kind == .key,
              let character = event.charactersIgnoringModifiers?.first,
              !character.isWhitespace else {
            NSSound.beep()
            return
        }
        let modifiers = event.modifierFlags.intersection(MacAppShortcut.significantModifiers)
        guard !modifiers.isEmpty else {
            reject("Include at least one modifier key.")
            return
        }
        onCommit?(
            MacAppShortcut(
                key: String(character).lowercased(),
                keyCode: event.keyCode,
                modifiers: modifiers
            )
        )
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        let modifiers = event.modifierFlags.intersection(MacAppShortcut.significantModifiers)
        switch kind {
        case .key:
            onDraft?(MacAppShortcut(key: nil, keyCode: nil, modifiers: modifiers))
        case .modifiers(let disallowsShift, let disallowsCommand):
            if !modifiers.isEmpty {
                pendingModifiers.formUnion(modifiers)
                onDraft?(MacAppShortcut(key: nil, keyCode: nil, modifiers: pendingModifiers))
                return
            }
            guard !pendingModifiers.isEmpty else { return }
            defer { pendingModifiers = [] }
            guard !disallowsShift || !pendingModifiers.contains(.shift) else {
                reject("Shift is reserved for all notes.")
                return
            }
            guard !disallowsCommand || !pendingModifiers.contains(.command) else {
                reject("Command is reserved for interacting with click-through notes.")
                return
            }
            onCommit?(MacAppShortcut(key: nil, keyCode: nil, modifiers: pendingModifiers))
        }
    }

    override func resignFirstResponder() -> Bool {
        let resigns = super.resignFirstResponder()
        guard resigns, isRecording else { return resigns }
        pendingModifiers = []
        onCancel?()
        return resigns
    }

    private func reject(_ message: LocalizedStringKey) {
        onValidationError?(message)
        onCancel?()
        NSSound.beep()
    }
}

private struct VisualEffectBlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: Private functions

extension SettingsForm {
    static func preferredWindowHeight(
        contentHeight: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        min(width, contentHeight)
    }

    static func backgroundTransparency(fromOpacity opacity: Double) -> Double {
        1 - min(max(opacity, 0), 1)
    }

    static func backgroundOpacity(fromTransparency transparency: Double) -> Double {
        1 - min(max(transparency, 0), 1)
    }

    static func crossesClickThroughThreshold(from oldValue: Double, to newValue: Double) -> Bool {
        crossesSliderMarker(
            from: oldValue,
            to: newValue,
            marker: NoteWindowClickThrough.minimumBackgroundTransparency
        )
    }

    static func crossesFontSizeDefault(from oldValue: Double, to newValue: Double) -> Bool {
        crossesSliderMarker(
            from: oldValue,
            to: newValue,
            marker: Double(FontSize.small.rawValue)
        )
    }

    static func crossesSliderMarker(from oldValue: Double, to newValue: Double, marker: Double) -> Bool {
        (oldValue < marker && newValue >= marker)
            || (oldValue >= marker && newValue < marker)
    }

    static func opacityPreviewValue(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8)
        return 0.25 + 0.75 * (0.5 + 0.5 * cos(phase * .pi / 4))
    }

    static func gatherPreviewProgress(at date: Date) -> CGFloat {
        movementPreviewProgress(at: date)
    }

    static func opacityChevronState(at date: Date) -> ScrollChevronState {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8)
        let opacity = opacityPreviewValue(at: date)
        let dimmingProgress = (1 - opacity) / 0.75
        return ScrollChevronState(
            travelOffset: CGFloat(dimmingProgress * 60),
            pointsDown: phase < 4,
            directionTransitionOpacity: directionTransitionOpacity(
                phase: phase,
                period: 8,
                reversalPoints: [0, 4]
            )
        )
    }

    static func gatherChevronState(at date: Date) -> ScrollChevronState {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5)
        return ScrollChevronState(
            travelOffset: gatherPreviewProgress(at: date) * 60,
            pointsDown: phase < 3,
            directionTransitionOpacity: directionTransitionOpacity(
                phase: phase,
                period: 5,
                reversalPoints: [0, 3]
            )
        )
    }

    private static func directionTransitionOpacity(
        phase: TimeInterval,
        period: TimeInterval,
        reversalPoints: [TimeInterval]
    ) -> Double {
        let fadeDuration = 0.35
        let distanceToReversal = reversalPoints.reduce(period) { currentDistance, point in
            let directDistance = abs(phase - point)
            let wrappedDistance = period - directDistance
            return min(currentDistance, min(directDistance, wrappedDistance))
        }
        return min(1, distanceToReversal / fadeDuration)
    }

    private static func movementPreviewProgress(at date: Date) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5)
        let linear: Double
        switch phase {
        case ..<0.5:
            linear = 0
        case ..<2.0:
            linear = (phase - 0.5) / 1.5
        case ..<3.0:
            linear = 1
        case ..<4.5:
            linear = 1 - (phase - 3.0) / 1.5
        default:
            linear = 0
        }
        let eased = linear * linear * (3 - 2 * linear)
        return CGFloat(eased)
    }

    static func alignment(for corner: ArrangementCorner) -> Alignment {
        switch corner {
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .topRight: .topTrailing
        case .topLeft: .topLeading
        }
    }
    
    static func edge(
        for corner: ArrangementCorner,
        withAlignment align: ArrangementAlignment
    ) -> Edge.Set {
        switch align {
        case .horizontal:
            switch corner {
            case .bottomLeft, .topLeft:
                return .trailing
            case .bottomRight, .topRight:
                return .leading
            }
        case .vertical:
            switch corner {
            case .bottomLeft, .bottomRight:
                return .top
            case .topLeft, .topRight:
                return .bottom
            }
        }
    }
    
    static func imageNameForTaskAppearance(with option: TaskLineTruncation) -> String {
        switch option {
        case .single: "taskTruncationSingle"
        case .multiple: "taskTruncationMultiple"
        }
    }
    
    static func taskAppearanceText(with option: TaskLineTruncation) -> Text {
        switch option {
        case .single: Text("Single line (ellipsis)")
        case .multiple: Text("Wrap to multiple lines")
        }
    }
}

// MARK: Enum types

enum FontSize: Double, CaseIterable {
    case xSmall = 10
    case small = 13
    case medium
    case large
    case xLarge = 24
    
    init?(fromLegacySetting legacyValue: Double) {
        self = FontSize.allCases[Int(legacyValue)]
    }
    
    static let storageKey = "fontSize"
}

enum TaskLineTruncation: Int {
    case single = 1
    case multiple
    
    static let storageKey = "taskLineTruncation"
}

enum ArrangementCorner: Int {
    case bottomLeft = 0
    case bottomRight
    case topRight
    case topLeft
    
    static let storageKey = "selectedArrangementCorner"
}

enum ArrangementAlignment: Int {
    case horizontal = 0
    case vertical
    
    static let storageKey = "selectedArrangementAlignment"
}

enum ArrangementSpacing: Int {
    case minimum = 20
    case medium = 40
    case maximum = 60
    
    static let sideStorageKey = "selectedArrangementSpacing"
    static let cornerStorageKey = "selectedArrangementCornerMargin"
}

// MARK: Color extension

extension NoteColor {
    static let storageKey = "noteColor"
    private static let legacyTranslucentRawValue = 6

    var legacyRawValue: Int {
        switch self {
        case .yellow: 0
        case .green: 1
        case .blue: 2
        case .pink: 3
        case .purple: 4
        case .orange: 5
        }
    }

    init?(legacyRawValue: Int) {
        switch legacyRawValue {
        case 0: self = .yellow
        case 1: self = .green
        case 2: self = .blue
        case 3: self = .pink
        case 4: self = .purple
        case 5: self = .orange
        default: return nil
        }
    }

    static func current(from defaults: UserDefaults = .standard) -> NoteColor {
        let rawValue = defaults.integer(forKey: storageKey)
        if rawValue == legacyTranslucentRawValue {
            defaults.set(NoteColor.yellow.legacyRawValue, forKey: storageKey)
            if defaults.object(forKey: NoteWindowBackground.opacityStorageKey) == nil {
                defaults.set(0.0, forKey: NoteWindowBackground.opacityStorageKey)
            }
        }
        return NoteColor(legacyRawValue: rawValue) ?? .yellow
    }

    static func storageKey(for noteID: NoteID) -> String {
        "noteColor.\(noteID.stringValue)"
    }

    static func legacyLocalColor(
        for noteID: NoteID,
        defaults: UserDefaults = .standard
    ) -> NoteColor? {
        let key = storageKey(for: noteID)
        guard defaults.object(forKey: key) != nil else { return nil }
        return NoteColor(legacyRawValue: defaults.integer(forKey: key))
    }

    var localizedLabel: String {
        switch self {
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .blue: String(localized: "Blue")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        case .orange: String(localized: "Orange")
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return .noteBackground
        case .green: return .systemNoteBackground
        case .blue: return .noteBlueBackground
        case .pink: return .notePinkBackground
        case .purple: return .notePurpleBackground
        case .orange: return .noteOrangeBackground
        }
    }

    var fillStyle: AnyShapeStyle {
        return AnyShapeStyle(Color(nsColor: nsColor))
    }
}

// MARK: Settings preview

#if DEBUG
#Preview {
    return SettingsForm()
}
#endif
