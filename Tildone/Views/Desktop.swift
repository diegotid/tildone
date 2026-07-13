//
//  Desktop.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

/// macOS-only window coordinator. It renders repository snapshots but owns no
/// persistence objects, contexts, or shared-store mutation rules.
struct Desktop: View {
    @ObservedObject var store: MacSharedStore
    @State private var noteWindows: [NoteID: NSWindow] = [:]
    @State private var closedNoteIDs: Set<NoteID> = []
    @State private var foregroundWindow: NSWindow?
    @State private var updateWindow: NSWindow?
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

    private static let appWindowIDs = [Id.aboutWindow, Id.updateWindow]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                setWindowOptions()
                openNoteWindows()
                createWhatsNewNoteIfNeeded()
            }
            .onChange(of: store.notes.map(\.id)) { _, _ in
                reconcileNoteWindows()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                Swift.Task { try? await store.deleteDeletableNotes() }
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
            .onReceive(NotificationCenter.default.publisher(for: .close)) { _ in handleClose() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
                if let window = event.object as? NSWindow { handleFocus(window) }
            }
    }
}

private extension Desktop {
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
        Note(store: store, noteID: note.id)
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
        window.setNoteStyle(noteColor: NoteColor.current())
        window.standardWindowButton(.closeButton)?.isEnabled = note.isDeletable
        window.contentView = NSHostingView(rootView: noteWindow(for: note))
        window.applyNoteBackground(isSystem: false)
        window.setFrameAutosaveName(note.legacyWindowKey)
        window.title = note.legacyWindowKey
        window.titleVisibility = .hidden
        let desiredOrigin = position.map {
            CGPoint(x: $0.x - window.frame.width / 2, y: $0.y - window.frame.height / 2)
        } ?? window.frame.origin
        window.setFrameOrigin(clampedOrigin(for: window, desiredOrigin: desiredOrigin, on: screenForNewWindow(at: position)))
        noteWindows[note.id] = window
        closedNoteIDs.remove(note.id)
        foregroundNoteID = note.id
        foregroundWindow = window
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

private struct MacSystemReleaseNote: View {
    let version: String?
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(version.map { "Updated to v\($0)" } ?? "Updated")
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
