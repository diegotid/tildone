//
//  Desktop.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

enum MacNoteWindowGeometry {
    static func repairingUndersizedRestoredFrame(
        _ frame: NSRect,
        minimumSize: NSSize,
        defaultSize: NSSize
    ) -> NSRect {
        guard frame.width < minimumSize.width || frame.height < minimumSize.height else {
            return frame
        }
        return NSRect(
            x: frame.minX,
            y: frame.maxY - defaultSize.height,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }
}

/// macOS-only window coordinator. It renders repository snapshots but owns no
/// persistence objects, contexts, or shared-store mutation rules.
struct Desktop: View {
    @ObservedObject var store: MacSharedStore
    let noteSyncIndicatorState: MacNoteSyncIndicatorState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var noteWindows: [NoteID: NSWindow] = [:]
    @State private var closedNoteIDs: Set<NoteID> = []
    @State private var foregroundWindow: NSWindow?
    @State private var updateWindow: NSWindow?
    @State private var opacityScrollMonitor = NoteOpacityScrollMonitor()
    @State private var clickThroughMonitor = NoteClickThroughMonitor()
    @State private var clickThroughHoverMonitor = NoteClickThroughHoverMonitor()
    @State private var hoveredClickThroughNoteID: NoteID?
    @State private var clickThroughBaseAlphas: [NoteID: CGFloat] = [:]
    @State private var clickThroughHintWindows: [NoteID: NSPanel] = [:]
    @State private var commandInteractionNoteID: NoteID?
    @State private var isClickThroughCommandPressed = false
    @State private var isFocusFilterTextBlurred = false
    @State private var focusFilterAllowsBackgroundNotes = false
    @Binding var foregroundNoteID: NoteID? {
        didSet { cleanUnfocusedNotes() }
    }

    @AppStorage(ArrangementCorner.storageKey)
    private var selectedArrangementCorner: ArrangementCorner = .bottomLeft
    @AppStorage(ArrangementAlignment.storageKey)
    private var selectedArrangementAlignment: ArrangementAlignment = .horizontal
    @AppStorage(ArrangementSpacing.cornerStorageKey)
    private var selectedArrangementCornerMargin: ArrangementSpacing = .medium
    @AppStorage(ArrangementSpacing.sideStorageKey)
    private var selectedArrangementSpacing: ArrangementSpacing = .minimum
    @AppStorage(NoteWindowClickThrough.storageKey)
    private var clickThroughNotes = false

    private static let appWindowIDs = [Id.aboutWindow, Id.syncStatusWindow, Id.updateWindow]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                setWindowOptions()
                if store.notes.isEmpty {
                    MenuBarController.shared.presentMenuForEmptyMenuBarOnlyWorkspace()
                }
                openNoteWindows()
                createWhatsNewNoteIfNeeded()
                updateCompletedTaskOrdering(
                    isEnabled: UserDefaults.standard.bool(
                        forKey: AppAppearance.moveCheckedTasksToEndStorageKey
                    )
                )
                installOpacityScrollMonitor()
                updateClickThroughMonitoring()
                updateClickThroughHoverMonitoring()
            }
            .onChange(of: store.notes.map(\.id)) { _, _ in
                reconcileNoteWindows()
            }
            .onChange(of: noteSyncIndicatorState) { _, state in
                setNoteSyncIndicatorState(state)
            }
            .onChange(of: clickThroughNotes) { _, _ in
                updateClickThroughMonitoring()
                updateClickThroughHoverMonitoring()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                arrangeNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arrange)) { _ in arrangeNotes() }
            .onReceive(NotificationCenter.default.publisher(for: .arrangeMinimized)) { _ in
                arrangeNotes(onlyMinimized: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .new)) { _ in
                createAndShowNewNote(at: foregroundWindowUpperRightCorner())
            }
            .onReceive(NotificationCenter.default.publisher(for: .visibility)) { notification in
                guard let (isTextBlurred, allowsBackgroundNotes) = notification.object as? (Bool, Bool) else {
                    return
                }
                isFocusFilterTextBlurred = isTextBlurred
                focusFilterAllowsBackgroundNotes = allowsBackgroundNotes
            }
            .onReceive(NotificationCenter.default.publisher(for: .close)) { _ in handleClose() }
            .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in openSettings() }
            .onReceive(NotificationCenter.default.publisher(for: .updateCompletedTaskOrdering)) { notification in
                guard let isEnabled = notification.object as? Bool else { return }
                updateCompletedTaskOrdering(isEnabled: isEnabled)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAbout)) { _ in
                openWindow(id: Id.aboutWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFocusFilterHelp)) { _ in
                openWindow(id: Id.focusFilterHelpWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
                if let window = event.object as? NSWindow { handleFocus(window) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { event in
                updateClickThroughHintPosition(for: event)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { event in
                updateClickThroughHintPosition(for: event)
            }
            .onDisappear {
                opacityScrollMonitor.stop()
                clickThroughMonitor.stop()
                clickThroughHoverMonitor.stop()
                closeManagedNoteWindows()
            }
    }
}

private extension Desktop {
    func updateCompletedTaskOrdering(isEnabled: Bool) {
        Swift.Task {
            do {
                try await store.applyCompletedTaskOrdering(enabled: isEnabled)
            } catch {
                UserDefaults.standard.set(
                    !isEnabled,
                    forKey: AppAppearance.moveCheckedTasksToEndStorageKey
                )
            }
        }
    }

    func closeManagedNoteWindows() {
        setClickThroughHoveredNote(nil)
        setClickThroughCommandInteractionNote(nil)
        closeClickThroughHintWindows()
        for window in noteWindows.values { window.close() }
        noteWindows.removeAll()
        closedNoteIDs.removeAll()
        foregroundWindow = nil
        foregroundNoteID = nil
    }

    func installOpacityScrollMonitor() {
        opacityScrollMonitor.start { event in
            handleOpacityScroll(event)
        }
    }

    func updateClickThroughMonitoring() {
        clickThroughMonitor.update(isEnabled: clickThroughNotes) { isCommandPressed in
            isClickThroughCommandPressed = isCommandPressed
            setClickThroughCommandInteractionNote(
                isCommandPressed ? hoveredNoteWindow()?.noteID : nil
            )
            applyClickThroughPreference(isCommandPressed: isCommandPressed)
            updateClickThroughHoverAppearance()
        }
    }

    func updateClickThroughHoverMonitoring() {
        guard clickThroughNotes else {
            clickThroughHoverMonitor.stop()
            setClickThroughHoveredNote(nil)
            setClickThroughCommandInteractionNote(nil)
            return
        }
        clickThroughHoverMonitor.start { point in
            updateClickThroughHoverAppearance(at: point)
        }
        updateClickThroughHoverAppearance()
    }

    func updateClickThroughHoverAppearance(at point: NSPoint = NSEvent.mouseLocation) {
        guard clickThroughNotes, !isClickThroughCommandPressed else {
            setClickThroughHoveredNote(nil)
            return
        }
        setClickThroughHoveredNote(hoveredNoteWindow(at: point)?.noteID)
    }

    func setClickThroughHoveredNote(_ noteID: NoteID?) {
        guard hoveredClickThroughNoteID != noteID else { return }
        if let previousNoteID = hoveredClickThroughNoteID {
            if let window = noteWindows[previousNoteID],
               let baseAlpha = clickThroughBaseAlphas.removeValue(forKey: previousNoteID) {
                animateWindowOpacity(window, to: baseAlpha)
            }
            hideClickThroughHint(for: previousNoteID)
        }
        hoveredClickThroughNoteID = noteID
        if let noteID, let window = noteWindows[noteID] {
            let baseAlpha = NoteWindowOpacity.currentAlpha(for: noteID)
            clickThroughBaseAlphas[noteID] = baseAlpha
            animateWindowOpacity(
                window,
                to: NoteWindowClickThrough.hoverAlpha(for: baseAlpha, isHovered: true)
            )
            showClickThroughHint(for: noteID, parent: window)
        }
    }

    func animateWindowOpacity(_ window: NSWindow, to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NoteWindowClickThrough.visualTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = alpha
        }
    }

    func setClickThroughCommandInteractionNote(_ noteID: NoteID?) {
        guard commandInteractionNoteID != noteID else { return }
        if let previousNoteID = commandInteractionNoteID {
            NotificationCenter.default.post(
                name: .noteWindowClickThroughCommandChanged,
                object: (previousNoteID, false)
            )
        }
        commandInteractionNoteID = noteID
        if let noteID {
            NotificationCenter.default.post(
                name: .noteWindowClickThroughCommandChanged,
                object: (noteID, true)
            )
        }
    }

    func showClickThroughHint(for noteID: NoteID, parent: NSWindow) {
        let hintWindow = clickThroughHintWindows[noteID] ?? makeClickThroughHintWindow()
        clickThroughHintWindows[noteID] = hintWindow
        positionClickThroughHint(hintWindow, over: parent)
        if hintWindow.parent !== parent {
            parent.addChildWindow(hintWindow, ordered: .above)
        }
        hintWindow.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NoteWindowClickThrough.visualTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            hintWindow.animator().alphaValue = 1
        }
    }

    func hideClickThroughHint(for noteID: NoteID) {
        guard let hintWindow = clickThroughHintWindows[noteID] else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NoteWindowClickThrough.visualTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            hintWindow.animator().alphaValue = 0
        }, completionHandler: {
            if hintWindow.alphaValue == 0 {
                hintWindow.orderOut(nil)
            }
        })
    }

    func closeClickThroughHintWindows() {
        for hintWindow in clickThroughHintWindows.values {
            hintWindow.close()
        }
        clickThroughHintWindows.removeAll()
    }

    func makeClickThroughHintWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: .init(x: 0, y: 0, width: Layout.defaultNoteWidth, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ClickThroughHint())
        return panel
    }

    func positionClickThroughHint(_ hintWindow: NSWindow, over parent: NSWindow) {
        hintWindow.setFrame(
            .init(
                x: parent.frame.minX,
                y: parent.frame.maxY - 30,
                width: parent.frame.width,
                height: 30
            ),
            display: false
        )
    }

    func updateClickThroughHintPosition(for event: Notification) {
        guard let parent = event.object as? NSWindow,
              let noteID = noteWindows.first(where: { $0.value === parent })?.key,
              let hintWindow = clickThroughHintWindows[noteID] else {
            return
        }
        positionClickThroughHint(hintWindow, over: parent)
    }

    func applyClickThroughPreference(isCommandPressed: Bool = NoteWindowClickThrough.isCommandPressed) {
        let ignoresMouseEvents = NoteWindowClickThrough.shouldIgnoreMouseEvents(
            isEnabled: clickThroughNotes,
            isCommandPressed: isCommandPressed
        )
        for window in noteWindows.values {
            window.ignoresMouseEvents = ignoresMouseEvents
        }
    }

    func openNoteWindows() {
        if store.notes.isEmpty {
            createAndShowNewNote(at: randomPositionOnScreen())
        } else {
            reconcileNoteWindows()
        }
    }

    func reconcileNoteWindows() {
        let activeIDs = Set(store.notes.map(\.id))
        for (id, window) in noteWindows where !activeIDs.contains(id) {
            if id == hoveredClickThroughNoteID {
                setClickThroughHoveredNote(nil)
            }
            if id == commandInteractionNoteID {
                setClickThroughCommandInteractionNote(nil)
            }
            clickThroughHintWindows.removeValue(forKey: id)?.close()
            clickThroughBaseAlphas.removeValue(forKey: id)
            window.close()
            noteWindows[id] = nil
            closedNoteIDs.remove(id)
        }
        for note in store.notes where noteWindows[note.id] == nil && !closedNoteIDs.contains(note.id) {
            openWindow(for: note)
        }
    }

    func createAndShowNewNote(at position: CGPoint) {
        Swift.Task {
            do {
                let note = try await store.createNote()
                openWindow(for: note, position: position)
            } catch {
                fatalError("Could not create a note: \(error)")
            }
        }
    }

    func handleFocus(_ window: NSWindow) {
        foregroundWindow = window
        if let noteID = noteWindows.first(where: { $0.value === window })?.key {
            foregroundNoteID = noteID
        } else if let windowID = window.identifier?.rawValue, Self.appWindowIDs.contains(windowID) {
            foregroundNoteID = nil
        }
    }

    func handleClose() {
        if let noteID = foregroundNoteID, let note = store.note(noteID), note.isDeletable {
            if noteID == hoveredClickThroughNoteID {
                setClickThroughHoveredNote(nil)
            }
            if noteID == commandInteractionNoteID {
                setClickThroughCommandInteractionNote(nil)
            }
            foregroundWindow?.close()
            noteWindows[noteID] = nil
            closedNoteIDs.insert(noteID)
        } else {
            foregroundWindow?.close()
        }
    }

    func cleanUnfocusedNotes() {
        for note in store.notes where note.id != foregroundNoteID {
            NotificationCenter.default.post(name: .clean, object: note.id)
        }
    }

    func setWindowOptions() {
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        Swift.Task {
            let filterIntent = try await FocusFilter.current
            _ = try await filterIntent.perform()
        }
    }

    func createWhatsNewNoteIfNeeded() {
        Swift.Task {
            guard await UpdateChecker.hasNewRelease() else { return }
            openSystemReleaseNote(version: UpdateChecker.pendingVersion)
        }
    }
}

private extension Desktop {
    func noteWindow(for note: MacNoteSnapshot) -> some View {
        Note(
            store: store,
            noteID: note.id,
            initialFocusBlurred: isFocusFilterTextBlurred
        )
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
                guard let window = event.object as? NSWindow else { return }
                foregroundWindow = window
                if noteWindows[note.id] === window {
                    foregroundNoteID = note.id
                } else if window.identifier?.rawValue == Id.aboutWindow {
                    foregroundNoteID = nil
                }
            }
    }

    func openWindow(for note: MacNoteSnapshot, position: CGPoint? = nil) {
        if let existingWindow = noteWindows[note.id] {
            foregroundNoteID = note.id
            foregroundWindow = existingWindow
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let layout = NSRect(x: 0, y: 0, width: Layout.defaultNoteWidth, height: Layout.defaultNoteHeight)
        let window = NSWindow(
            contentRect: layout,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless],
            backing: .buffered,
            defer: false
        )
        window.setNoteStyle(noteColor: note.color)
        window.level = focusFilterAllowsBackgroundNotes ? .normal : .floating
        window.ignoresMouseEvents = NoteWindowClickThrough.shouldIgnoreMouseEvents(
            isEnabled: clickThroughNotes,
            isCommandPressed: isClickThroughCommandPressed
        )
        let windowAlpha = NoteWindowOpacity.currentAlpha(for: note.id)
        window.alphaValue = windowAlpha
        window.standardWindowButton(.closeButton)?.isEnabled = note.isDeletable
        window.contentView = NSHostingView(rootView: noteWindow(for: note))
        addNoteColorPicker(to: window, noteID: note.id)
        window.applyNoteBackgroundColor(
            note.color.nsColor,
            alpha: NoteWindowBackground.tintAlpha(
                configuredAlpha: NoteWindowBackground.currentAlpha(),
                windowAlpha: windowAlpha
            )
        )
        window.setFrameAutosaveName(note.legacyWindowKey)
        repairUndersizedRestoredFrame(of: window)
        window.title = note.legacyWindowKey
        window.titleVisibility = .hidden
        let desiredOrigin = position.map {
            CGPoint(x: $0.x - window.frame.width / 2, y: $0.y - window.frame.height / 2)
        } ?? window.frame.origin
        window.setFrameOrigin(clampedOrigin(for: window, desiredOrigin: desiredOrigin, on: screenForNewWindow(at: position)))
        noteWindows[note.id] = window
        updateClickThroughHoverAppearance()
        closedNoteIDs.remove(note.id)
        foregroundNoteID = note.id
        foregroundWindow = window
    }

    func repairUndersizedRestoredFrame(of window: NSWindow) {
        let minimumFrameSize = window.frameRect(forContentRect: NSRect(
            origin: .zero,
            size: NSSize(width: Layout.minNoteWidth, height: Layout.minNoteHeight)
        )).size
        let defaultFrameSize = window.frameRect(forContentRect: NSRect(
            origin: .zero,
            size: NSSize(width: Layout.defaultNoteWidth, height: Layout.defaultNoteHeight)
        )).size
        let repairedFrame = MacNoteWindowGeometry.repairingUndersizedRestoredFrame(
            window.frame,
            minimumSize: minimumFrameSize,
            defaultSize: defaultFrameSize
        )
        guard repairedFrame != window.frame else { return }
        window.setFrame(repairedFrame, display: false)
    }

    func handleOpacityScroll(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == .command || modifiers == [.command, .shift],
              let delta = NoteWindowOpacity.wheelDelta(for: event),
              let hovered = hoveredNoteWindow() else {
            return false
        }

        if modifiers.contains(.shift) {
            adjustAllNoteWindowOpacities(by: delta)
        } else {
            setOpacity(
                NoteWindowOpacity.adjustedAlpha(hovered.window.alphaValue, by: delta),
                for: hovered.noteID,
                window: hovered.window
            )
        }
        return true
    }

    func hoveredNoteWindow(at point: NSPoint = NSEvent.mouseLocation) -> (noteID: NoteID, window: NSWindow)? {
        let hovered = noteWindows.filter { _, window in
            window.isVisible && window.isOnActiveSpace && window.frame.contains(point)
        }
        guard !hovered.isEmpty else { return nil }

        for window in NSApp.orderedWindows {
            if let match = hovered.first(where: { $0.value === window }) {
                return (match.key, match.value)
            }
        }
        guard let match = hovered.first else { return nil }
        return (match.key, match.value)
    }

    func adjustAllNoteWindowOpacities(by delta: CGFloat) {
        let notesAndWindows = noteWindows.map { (noteID: $0.key, window: $0.value) }
        let adjusted = NoteWindowOpacity.adjustedAlphas(
            notesAndWindows.map { $0.window.alphaValue },
            by: delta
        )
        for (entry, alpha) in zip(notesAndWindows, adjusted) {
            setOpacity(alpha, for: entry.noteID, window: entry.window)
        }
    }

    func setOpacity(_ alpha: CGFloat, for noteID: NoteID, window: NSWindow) {
        guard alpha != window.alphaValue else { return }
        window.alphaValue = alpha
        NoteWindowOpacity.setAlpha(alpha, for: noteID)
        NotificationCenter.default.post(name: .noteWindowOpacityChanged, object: window)
    }

    func addNoteColorPicker(to window: NSWindow, noteID: NoteID) {
        guard let contentView = window.contentView,
              let themeFrame = contentView.superview,
              let closeButton = window.standardWindowButton(.closeButton) else {
            return
        }

        let picker = NoteColorPickerTitlebarControl(store: store, noteID: noteID)
        let pickerSize = NSSize(
            width: MacNoteTitlebarLayout.colorPickerWidth,
            height: MacNoteTitlebarLayout.controlHeight
        )
        let closeButtonFrame = closeButton.convert(closeButton.bounds, to: themeFrame)
        picker.frame = NSRect(
            x: themeFrame.bounds.maxX - pickerSize.width - MacNoteTitlebarLayout.trailingMargin,
            y: closeButtonFrame.midY - pickerSize.height / 2 - 4,
            width: pickerSize.width,
            height: pickerSize.height
        )
        picker.autoresizingMask = [.minXMargin, .minYMargin]
        themeFrame.addSubview(picker, positioned: .above, relativeTo: nil)

        guard noteSyncIndicatorState != .hidden else { return }
        addNoteSyncIndicator(to: themeFrame, beside: picker, state: noteSyncIndicatorState)
    }

    func addNoteSyncIndicator(
        to themeFrame: NSView,
        beside picker: NSView,
        state: MacNoteSyncIndicatorState
    ) {
        let indicator = MacNoteSyncTitlebarControl(state: state)
        let indicatorSize = NSSize(
            width: MacNoteTitlebarLayout.syncIndicatorWidth,
            height: MacNoteTitlebarLayout.controlHeight
        )
        indicator.frame = NSRect(
            x: picker.frame.minX - indicatorSize.width - MacNoteTitlebarLayout.controlSpacing,
            y: picker.frame.minY,
            width: indicatorSize.width,
            height: indicatorSize.height
        )
        indicator.autoresizingMask = [.minXMargin, .minYMargin]
        themeFrame.addSubview(indicator, positioned: .above, relativeTo: nil)
    }

    func setNoteSyncIndicatorState(_ state: MacNoteSyncIndicatorState) {
        for window in noteWindows.values {
            guard let themeFrame = window.contentView?.superview else { continue }
            themeFrame.subviews
                .compactMap { $0 as? MacNoteSyncTitlebarControl }
                .forEach { $0.removeFromSuperview() }
            guard state != .hidden,
                  let picker = themeFrame.subviews.first(where: { $0 is NoteColorPickerTitlebarControl }) else {
                continue
            }
            addNoteSyncIndicator(to: themeFrame, beside: picker, state: state)
        }
    }

    func openSystemReleaseNote(version: String?) {
        if let updateWindow {
            updateWindow.makeKeyAndOrderFront(nil)
            return
        }
        let layout = NSRect(x: 0, y: 0, width: Layout.defaultNoteWidth, height: Layout.defaultNoteHeight)
        let window = NSWindow(
            contentRect: layout,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(Id.updateWindow)
        window.setNoteStyle(noteColor: .green)
        window.contentView = NSHostingView(rootView: MacSystemReleaseNote(version: version) {
            UpdateChecker.dismissPendingReleaseNote()
            window.close()
            updateWindow = nil
        })
        window.applyNoteBackground(isSystem: true)
        window.setFrameAutosaveName("TildoneUpdateNote")
        window.titleVisibility = .hidden
        updateWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func arrangeNotes(onlyMinimized: Bool = false) {
        let horizontal = selectedArrangementAlignment == .horizontal
        let inverse = horizontal
            ? [.bottomRight, .topRight].contains(selectedArrangementCorner)
            : [.topLeft, .topRight].contains(selectedArrangementCorner)
        for windows in noteWindowScreenMap().values {
            let sorted = windows.sorted {
                switch (horizontal, inverse) {
                case (true, true): $0.frame.origin.x > $1.frame.origin.x
                case (true, false): $0.frame.origin.x < $1.frame.origin.x
                case (false, true): $0.frame.origin.y > $1.frame.origin.y
                case (false, false): $0.frame.origin.y < $1.frame.origin.y
                }
            }.filter { !onlyMinimized || $0.title.starts(with: "_") }
            positionOnScreen(sorted)
        }
    }

    func noteWindowScreenMap() -> [NSScreen: [NSWindow]] {
        Dictionary(grouping: noteWindows.values.compactMap { $0.screen == nil ? nil : $0 }, by: { $0.screen! })
    }

    func positionOnScreen(_ windows: [NSWindow], from: Int = 0) {
        guard let window = windows.first, let screenFrame = window.screen?.frame else { return }
        let margin = from > 0 ? selectedArrangementSpacing.rawValue : selectedArrangementCornerMargin.rawValue
        let newPosition = from + margin
        let horizontal = selectedArrangementAlignment == .horizontal
        let inverseX = [.bottomRight, .topRight].contains(selectedArrangementCorner)
        let inverseY = [.topLeft, .topRight].contains(selectedArrangementCorner)
        let newX = horizontal ? newPosition : selectedArrangementCornerMargin.rawValue
        let newY = horizontal ? selectedArrangementCornerMargin.rawValue : newPosition
        let x = inverseX ? Int(screenFrame.width) - newX - Int(window.frame.width) : newX
        let y = inverseY ? Int(screenFrame.height) - Frame.menuBarHeight - newY - Int(window.frame.height) : newY
        let frame = NSRect(
            x: x + Int(screenFrame.origin.x), y: y + Int(screenFrame.origin.y),
            width: Int(window.frame.width), height: Int(window.frame.height)
        )
        DispatchQueue.main.async { withAnimation { window.setFrame(frame, display: false, animate: true) } }
        positionOnScreen(Array(windows.dropFirst()), from: newPosition + Int(horizontal ? window.frame.width : window.frame.height))
    }

    func screenForNewWindow(at position: CGPoint?) -> NSScreen {
        if let position, let screen = NSScreen.screens.first(where: { $0.frame.contains(position) }) { return screen }
        if let screen = foregroundWindow?.screen { return screen }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    func clampedOrigin(for window: NSWindow, desiredOrigin: CGPoint, on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        let maxX = max(visible.minX, visible.maxX - window.frame.width)
        let maxY = max(visible.minY, visible.maxY - window.frame.height)
        return CGPoint(x: min(max(desiredOrigin.x, visible.minX), maxX), y: min(max(desiredOrigin.y, visible.minY), maxY))
    }

    func foregroundWindowUpperRightCorner() -> CGPoint {
        guard let window = foregroundWindow else { return randomPositionOnScreen() }
        return CGPoint(x: window.frame.maxX, y: window.frame.maxY)
    }

    func randomPositionOnScreen() -> CGPoint {
        let frame = NSScreen.main?.frame ?? .zero
        let margin = CGFloat(selectedArrangementCornerMargin.rawValue)
        return CGPoint(
            x: CGFloat.random(in: frame.minX...(frame.maxX - Layout.defaultNoteWidth - margin)),
            y: CGFloat.random(in: frame.minY...(frame.maxY - Layout.defaultNoteHeight - margin))
        )
    }
}

private final class NoteOpacityScrollMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start(handler: @escaping (NSEvent) -> Bool) {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handler(event) ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            _ = handler(event)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        stop()
    }
}

private final class NoteClickThroughMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var modifierTimer: Timer?
    private var handler: ((Bool) -> Void)?
    private var isCommandPressed = false

    func update(isEnabled: Bool, handler: @escaping (Bool) -> Void) {
        self.handler = handler
        guard isEnabled else {
            stop()
            handler(false)
            return
        }

        if localMonitor == nil, globalMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handle(event)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handle(event)
            }
        }
        if modifierTimer == nil {
            modifierTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                self?.updateCommandState(NoteWindowClickThrough.isCommandPressed)
            }
        }
        isCommandPressed = !NoteWindowClickThrough.isCommandPressed
        updateCommandState(NoteWindowClickThrough.isCommandPressed)
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        modifierTimer?.invalidate()
        modifierTimer = nil
        handler = nil
    }

    deinit {
        stop()
    }

    private func handle(_ event: NSEvent) {
        updateCommandState(event.modifierFlags.contains(.command))
    }

    private func updateCommandState(_ isCommandPressed: Bool) {
        guard self.isCommandPressed != isCommandPressed else { return }
        self.isCommandPressed = isCommandPressed
        handler?(isCommandPressed)
    }
}

private final class NoteClickThroughHoverMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start(handler: @escaping (NSPoint) -> Void) {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            handler(NSEvent.mouseLocation)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            handler(NSEvent.mouseLocation)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        stop()
    }
}

private struct ClickThroughHint: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "command")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text("+")
            Text("click to interact")
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.primary)
        .padding(.leading, MacNoteTitlebarLayout.titleLeadingInset)
        .padding(.trailing, MacNoteTitlebarLayout.titleTrailingInset)
        .offset(y: -1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

private struct MacSystemReleaseNote: View {
    let version: String?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(version.map { String(localized: "Updated to v\($0)") } ?? String(localized: "Updated"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("New features:\n• Ability to change color and adjust the transparency of notes\n• Enhanced keyboard navigation for the task list")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Link("Visit release notes", destination: UpdateChecker.Remote.releaseNotesURL)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Dismiss", action: dismiss).buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(minWidth: Layout.minNoteWidth, minHeight: Layout.minNoteHeight)
    }
}
