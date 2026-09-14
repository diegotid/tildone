//
//  MacNoteTitlebarAccessoryController.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

/// Hosts Tildone's custom controls through AppKit's supported titlebar API.
/// Direct children of `NSThemeFrame` are private AppKit implementation details.
final class MacNoteTitlebarAccessoryController: NSTitlebarAccessoryViewController {
    private let colorPicker: NSView
    private let formatControl: NSHostingView<MacTaskTextFormatMenu>
    private let kindControl: NSHostingView<MacNoteKindMenu>
    private let focusPrivacyControl: NSHostingView<MacNoteFocusPrivacyMenu>
    private let initialSyncIndicatorState: MacNoteSyncIndicatorState
    private var syncIndicator: MacNoteSyncTitlebarControl?
    private var restoreControl: MinimizedNoteRestoreTitlebarControl?

    init(
        colorPicker: NSView,
        syncIndicatorState: MacNoteSyncIndicatorState,
        store: MacSharedStore,
        presentation: MacNotePresentation,
        noteID: NoteID,
        focusPrivacy: NoteFocusPrivacyState
    ) {
        self.colorPicker = colorPicker
        let formatControl = NSHostingView(rootView: MacTaskTextFormatMenu(
            store: store, presentation: presentation, noteID: noteID
        ))
        let kindControl = NSHostingView(rootView: MacNoteKindMenu(
            store: store, presentation: presentation, noteID: noteID
        ))
        let focusPrivacyControl = NSHostingView(rootView: MacNoteFocusPrivacyMenu(
            noteID: noteID,
            initialState: focusPrivacy
        ))
        // These controls are positioned explicitly beside the AppKit color
        // picker. Prevent localized SwiftUI menu content from changing their
        // hosting-view frames after the titlebar has laid them out.
        formatControl.sizingOptions = []
        kindControl.sizingOptions = []
        focusPrivacyControl.sizingOptions = []
        self.formatControl = formatControl
        self.kindControl = kindControl
        self.focusPrivacyControl = focusPrivacyControl
        initialSyncIndicatorState = syncIndicatorState
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: MacNoteTitlebarLayout.accessoryWidth,
            height: MacNoteTitlebarLayout.controlHeight
        ))
        view = container
        colorPicker.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(colorPicker)
        container.addSubview(formatControl)
        container.addSubview(kindControl)
        container.addSubview(focusPrivacyControl)
        installSyncIndicator(for: initialSyncIndicatorState)
        layoutControls()
    }

    func setSyncIndicatorState(_ state: MacNoteSyncIndicatorState) {
        loadViewIfNeeded()
        syncIndicator?.removeFromSuperview()
        syncIndicator = nil
        installSyncIndicator(for: state)
        layoutControls()
    }

    func setColorPickerHidden(_ hidden: Bool) {
        loadViewIfNeeded()
        colorPicker.isHidden = hidden
        formatControl.isHidden = hidden
        kindControl.isHidden = hidden
        focusPrivacyControl.isHidden = hidden
    }

    func setFormatControlForeground(_ foreground: Color) {
        loadViewIfNeeded()
        formatControl.rootView = MacTaskTextFormatMenu(
            store: formatControl.rootView.store,
            presentation: formatControl.rootView.presentation,
            noteID: formatControl.rootView.noteID,
            foreground: foreground
        )
        formatControl.needsLayout = true
        formatControl.needsDisplay = true
        kindControl.rootView = MacNoteKindMenu(
            store: kindControl.rootView.store,
            presentation: kindControl.rootView.presentation,
            noteID: kindControl.rootView.noteID,
            foreground: foreground
        )
        focusPrivacyControl.rootView = MacNoteFocusPrivacyMenu(
            noteID: focusPrivacyControl.rootView.noteID,
            initialState: focusPrivacyControl.rootView.initialState,
            foreground: foreground
        )
    }

    func setRestoreControlVisible(
        _ visible: Bool,
        foreground: Color,
        onRestore: @escaping () -> Void
    ) {
        loadViewIfNeeded()
        guard visible else {
            restoreControl?.removeFromSuperview()
            restoreControl = nil
            return
        }
        guard restoreControl == nil else {
            restoreControl?.setForeground(foreground)
            return
        }
        let restoreControl = MinimizedNoteRestoreTitlebarControl(
            onRestore: onRestore,
            foreground: foreground
        )
        restoreControl.autoresizingMask = [.minXMargin, .minYMargin]
        view.addSubview(restoreControl)
        self.restoreControl = restoreControl
        layoutControls()
    }

    func setRestoreControlForeground(_ foreground: Color) {
        restoreControl?.setForeground(foreground)
    }

    private func installSyncIndicator(for state: MacNoteSyncIndicatorState) {
        guard state != .hidden else { return }
        let indicator = MacNoteSyncTitlebarControl(state: state)
        indicator.autoresizingMask = [.minXMargin, .minYMargin]
        view.addSubview(indicator)
        syncIndicator = indicator
    }

    private func layoutControls() {
        let accessoryWidth = MacNoteTitlebarLayout.accessoryWidth
        if abs(view.frame.width - accessoryWidth) > 0.5 {
            view.setFrameSize(NSSize(width: accessoryWidth, height: view.frame.height))
        }
        colorPicker.frame = MacNoteTitlebarLayout.colorPickerFrame(in: view.bounds)
        formatControl.frame = MacNoteTitlebarLayout.formatControlFrame(
            alignedWith: colorPicker.frame
        )
        kindControl.frame = MacNoteTitlebarLayout.kindControlFrame(alignedWith: colorPicker.frame)
        focusPrivacyControl.frame = MacNoteTitlebarLayout.focusPrivacyControlFrame(
            alignedWith: colorPicker.frame
        )
        syncIndicator?.frame = MacNoteTitlebarLayout.syncIndicatorFrame(
            alignedWith: colorPicker.frame
        )
        restoreControl?.frame = MacNoteTitlebarLayout.minimizedRestoreFrame(
            in: view.bounds,
            alignedWith: colorPicker.frame
        )
    }
}

private struct MacNoteFocusPrivacyMenu: View {
    let noteID: NoteID
    let initialState: NoteFocusPrivacyState
    var foreground: Color = .primary
    @State private var state: NoteFocusPrivacyState
    @State private var focusBlurred: Bool
    @State private var focusAllowsBackground: Bool
    @State private var usesFocusFilterDefaults: Bool

    init(
        noteID: NoteID,
        initialState: NoteFocusPrivacyState,
        foreground: Color = .primary
    ) {
        self.noteID = noteID
        self.initialState = initialState
        self.foreground = foreground
        _state = State(initialValue: initialState)
        _focusBlurred = State(initialValue: initialState.isContentBlurred)
        _focusAllowsBackground = State(initialValue: initialState.staysInBackground)
        _usesFocusFilterDefaults = State(initialValue:
            NoteFocusPrivacySettings.blurOverride(for: noteID) == nil
                && NoteFocusPrivacySettings.backgroundOverride(for: noteID) == nil
        )
    }

    var body: some View {
        Menu {
            Toggle(isOn: Binding(
                get: { state.isContentBlurred },
                set: setContentBlurred
            )) {
                Label(
                    "Blur Content",
                    systemImage: "drop"
                )
            }
            Toggle(isOn: Binding(
                get: { state.staysInBackground },
                set: setStaysInBackground
            )) {
                Label(
                    "Stay in Background",
                    systemImage: "macwindow.on.rectangle"
                )
            }
            Divider()
            Button(
                usesFocusFilterDefaults
                    ? "Using Focus Filter Defaults"
                    : "Use Focus Filter Defaults",
                action: resetToFocusFilterDefaults
            )
            .disabled(usesFocusFilterDefaults)
        } label: {
            Image(systemName: usesFocusFilterDefaults ? "moon" : "moon.fill")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foreground)
                .frame(
                    width: MacNoteTitlebarLayout.focusPrivacyControlWidth,
                    height: MacNoteTitlebarLayout.controlHeight
                )
                .contentShape(Rectangle())
                .offset(y: 3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(foreground)
        .help("Focus & Privacy")
        .accessibilityLabel("Focus & Privacy")
        .onReceive(NotificationCenter.default.publisher(for: .visibility)) { notification in
            guard let (blurred, allowsBackground) = notification.object as? (Bool, Bool) else { return }
            focusBlurred = blurred
            focusAllowsBackground = allowsBackground
            refreshState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteFocusPrivacyChanged)) { notification in
            guard let changedState = notification.object as? NoteFocusPrivacyState,
                  changedState.noteID == noteID else { return }
            state = changedState
        }
    }

    private func setContentBlurred(_ isBlurred: Bool) {
        NoteFocusPrivacySettings.setBlurOverride(
            isBlurred == focusBlurred ? nil : isBlurred,
            for: noteID
        )
        refreshState()
    }

    private func setStaysInBackground(_ staysInBackground: Bool) {
        NoteFocusPrivacySettings.setBackgroundOverride(
            staysInBackground == focusAllowsBackground ? nil : staysInBackground,
            for: noteID
        )
        refreshState()
    }

    private func resetToFocusFilterDefaults() {
        NoteFocusPrivacySettings.setBlurOverride(nil, for: noteID)
        NoteFocusPrivacySettings.setBackgroundOverride(nil, for: noteID)
        refreshState()
    }

    private func refreshState() {
        usesFocusFilterDefaults = NoteFocusPrivacySettings.blurOverride(for: noteID) == nil
            && NoteFocusPrivacySettings.backgroundOverride(for: noteID) == nil
        state = NoteFocusPrivacySettings.state(
            for: noteID,
            focusBlurred: focusBlurred,
            focusAllowsBackground: focusAllowsBackground
        )
        NotificationCenter.default.post(name: .noteFocusPrivacyChanged, object: state)
    }
}

private struct MacNoteKindMenu: View {
    let store: MacSharedStore
    @ObservedObject var presentation: MacNotePresentation
    let noteID: NoteID
    var foreground: Color = .primary

    var body: some View {
        Menu {
            Button { setKind(.checklist) } label: {
                Label("Task list", systemImage: "checklist")
            }
            Button { setKind(.singleTask) } label: {
                Label("Single memo", systemImage: "text.aligncenter")
            }
        } label: {
            Image(systemName: presentation.snapshot.kind == .checklist ? "checklist" : "text.aligncenter")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foreground)
                .frame(width: MacNoteTitlebarLayout.kindControlWidth, height: MacNoteTitlebarLayout.controlHeight)
                .contentShape(Rectangle())
                .offset(y: 3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(foreground)
        .help("Note type")
        .accessibilityLabel("Note type")
    }

    private func setKind(_ kind: NoteKind) {
        Swift.Task { try? await store.setKind(kind, for: noteID) }
    }
}

extension NSWindow {
    var noteTitlebarAccessoryController: MacNoteTitlebarAccessoryController? {
        if let noteWindow = self as? MacNoteWindow,
           noteWindow.hasDetachedTitlebarAccessories {
            return noteWindow.detachedNoteTitlebarAccessoryController
        }
        return titlebarAccessoryViewControllers
            .compactMap { $0 as? MacNoteTitlebarAccessoryController }
            .first
    }
}
