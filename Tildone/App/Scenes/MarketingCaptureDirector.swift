#if MARKETING_CAPTURE
import AppKit
import SwiftUI
import TildoneDomain
import TildonePersistence

/// Disposable capture director, compiled out of ordinary builds.
@available(macOS 15, *)
@MainActor
final class MarketingCaptureDirector: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var headline = "A little less on your mind."
    @Published private(set) var compactNoteID: NoteID?
    private var stage: NSWindow!
    private var windows: [MacNoteWindow] = []
    private var noteIDs: [NoteID] = []
    private var store: MacSharedStore!
    private var recorder = MarketingCaptureRecorder()
    private var cursor: NSWindow!
    private var backgroundDocument: NSWindow!
    private var activatedBackgroundDocument = false
    private var run: Swift.Task<Void, Never>?
    private var startTime: Date?
    private let expandedNoteScale: CGFloat = 0.75
    private let bottomLeftGatherFactor: CGFloat = 0.75
    private let compactEdgeMargin: CGFloat = 47.5
    private var outputDirectory: URL {
        URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "MarketingOutputDirectory") as! String,
            isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        run = Swift.Task {
            do { try await prepare(); try await record() }
            catch {
                writeStatus("ERROR: \(error)")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func prepare() async throws {
        UserDefaults.standard.register(defaults: [
            FontSize.storageKey: 20.0,
            TaskLineTruncation.storageKey: TaskLineTruncation.multiple.rawValue,
            NoteWindowBackground.opacityStorageKey: 0.72,
            "taskSpellCheckingEnabled": false,
            "completedWelcomeOnboarding": true,
            "seenWhatsNewContent": WhatsNewRelease.contentID
        ])
        SingleMemoTypography.registerBundledFonts()
        let repository = try TildoneRepository(descriptor: .inMemory())
        store = MacSharedStore(repository: repository)
        store.setUndoEnabled(false)
        let fixture: [(String, NoteColor, [(String, Bool)], CGPoint)] = [
            (String(localized: "Today"), .yellow, [
                (String(localized: "Review the draft"), true),
                (String(localized: "Confirm the meeting"), true),
                (String(localized: "Send the proposal"), false)
            ], CGPoint(x: 105, y: 270)),
            (String(localized: "Home"), .blue, [
                (String(localized: "Call the electrician"), false),
                (String(localized: "Pick up the parcel"), false)
            ], CGPoint(x: 550, y: 215)),
            (String(localized: "Weekend"), .pink, [
                (String(localized: "Choose a walking route"), false),
                (String(localized: "Book a table"), false)
            ], CGPoint(x: 1000, y: 270))
        ]
        var notes: [MacNoteSnapshot] = []
        for (title, color, tasks, _) in fixture {
            let note = try await store.createNote(color: color)
            try await store.renameNote(note.id, to: title)
            for (text, completed) in tasks {
                let task = try await store.addTask(to: note.id, text: text)
                if completed { _ = try await store.setTaskCompletion(task.id, completed: true) }
            }
            notes.append(store.note(note.id)!)
        }
        guard let screen = NSScreen.main,
              let wallpaper = NSImage(contentsOfFile: Bundle.main.path(forResource: "GoldenGate", ofType: "png") ?? "") else {
            throw NSError(domain: "MarketingCapture", code: 2)
        }
        stage = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX - 720,
                                             y: screen.visibleFrame.midY - 405,
                                             width: 1440, height: 810),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        stage.isReleasedWhenClosed = false
        stage.title = "Tildone Marketing Preview"
        stage.appearance = NSAppearance(named: .aqua)
        stage.contentView = NSHostingView(rootView: MarketingCaptureBackdrop(director: self, wallpaper: wallpaper))
        stage.orderFront(nil)
        for (index, note) in notes.enumerated() {
            let windowScale: CGFloat = index == 0 ? 1.15 : (index == 1 ? 0.85 : 1)
            makeWindow(note: note, origin: fixture[index].3, windowScale: windowScale)
        }
        makeBackgroundMailWindow()
        // Move only the expanded blue and pink notes. Their compact
        // presentation keeps the established bottom-left edge margin.
        for window in [windows[1], windows[2]] {
            window.setFrameOrigin(NSPoint(x: window.frame.minX,
                                          y: window.frame.minY - window.frame.height * 0.25))
        }
        cursor = NSWindow(contentRect: NSRect(x: stage.frame.minX + 280, y: stage.frame.minY + 120,
                                              width: 30, height: 36),
                          styleMask: .borderless, backing: .buffered, defer: false)
        cursor.isOpaque = false
        cursor.backgroundColor = .clear
        cursor.hasShadow = false
        cursor.ignoresMouseEvents = true
        let image = NSImageView(frame: NSRect(x: 0, y: 0, width: 23, height: 30))
        image.image = NSCursor.arrow.image
        image.imageScaling = .scaleProportionallyUpOrDown
        cursor.contentView = image
        stage.addChildWindow(cursor, ordered: .above)
        cursor.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[1].makeKeyAndOrderFront(nil)
        try await Swift.Task.sleep(for: .seconds(2))
        for window in windows { window.makeFirstResponder(nil) }
        writeStatus("READY")
    }

    private func makeBackgroundMailWindow() {
        // An offline fictional inbox in a native window. Start with revision 4's
        // outer dimensions, then enlarge both dimensions without scaling text.
        backgroundDocument = NSWindow(
            contentRect: NSRect(x: stage.frame.minX + 380, y: stage.frame.minY + 130,
                                width: 780, height: 330),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        backgroundDocument.isReleasedWhenClosed = false
        backgroundDocument.title = String(localized: "Mail")
        backgroundDocument.appearance = NSAppearance(named: .aqua)
        backgroundDocument.tabbingMode = .disallowed
        backgroundDocument.level = .normal
        backgroundDocument.alphaValue = 0.82
        let host = NSHostingView(rootView: MarketingCaptureMail())
        host.sizingOptions = []
        backgroundDocument.contentView = host
        backgroundDocument.setFrame(NSRect(
            x: windows[1].frame.midX + 195,
            y: windows[1].frame.minY,
            width: 390 * 1.25,
            height: 308 * 1.25
        ), display: false)
        stage.addChildWindow(backgroundDocument, ordered: .above)
        backgroundDocument.orderFront(nil)
    }

    private func makeWindow(note: MacNoteSnapshot, origin: CGPoint, windowScale: CGFloat) {
        let window = MacNoteWindow(contentRect: NSRect(x: stage.frame.minX + origin.x,
                                                      y: stage.frame.minY + origin.y,
                                                      width: 330, height: 335),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless],
                                   backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setNoteStyle(noteColor: note.color)
        // Capture content is scaled by 0.75, so use the equivalent physical
        // minimum rather than clamping the smaller Home window to 240 pt high.
        window.contentMinSize = NSSize(width: Layout.minNoteWidth * expandedNoteScale,
                                       height: Layout.minNoteHeight * expandedNoteScale)
        window.title = note.legacyWindowKey
        window.titleVisibility = .hidden
        let presentation = store.presentation(for: note.id)!
        window.setNoteHostingContentView(NSHostingView(rootView: MarketingCaptureNote(
            director: self, store: store, presentation: presentation, noteID: note.id
        )))
        let accessory = MacNoteTitlebarAccessoryController(
            colorPicker: NoteColorPickerTitlebarControl(store: store, presentation: presentation, noteID: note.id),
            syncIndicatorState: .hidden, store: store, presentation: presentation, noteID: note.id)
        window.addTitlebarAccessoryViewController(accessory)
        window.applyNoteBackgroundColor(note.color.nsColor, alpha: 0.72)
        // Vary only window dimensions in this revision. The content transform
        // stays at 0.75 for all three notes, including completion overlays.
        let originalSize = window.frame.size
        window.setFrame(NSRect(
            x: stage.frame.minX + origin.x * bottomLeftGatherFactor,
            y: stage.frame.minY + origin.y * bottomLeftGatherFactor,
            width: originalSize.width * expandedNoteScale * windowScale,
            height: originalSize.height * expandedNoteScale * windowScale
        ), display: false)
        stage.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        windows.append(window)
        noteIDs.append(note.id)
    }

    private func record() async throws {
        let openingWindowSizes = windows.map { ["width": $0.frame.width, "height": $0.frame.height] }
        let openingWindowOrigins = windows.map { ["x": $0.frame.minX - stage.frame.minX,
                                                   "y": $0.frame.minY - stage.frame.minY] }
        let url = outputDirectory.appendingPathComponent("Tildone-macOS-preview-raw.mp4")
        try? FileManager.default.removeItem(at: url)
        try await recorder.start(windowID: CGWindowID(stage.windowNumber), destination: url)
        startTime = Date()
        writeStatus("RECORDING")
        try await wait(until: 0.6)
        try await demonstrateFloatingNotes()
        try await wait(until: 3)
        let checkboxes = descendants(windows[0].contentView!).compactMap { $0 as? Checkbox.ClickControl }
            .filter { $0.isEnabled && !$0.isChecked }
        guard let checkbox = checkboxes.first else { throw NSError(domain: "MarketingCapture", code: 3) }
        try await moveCursor(to: checkbox, duration: 1.1)
        try await wait(until: 5.8)
        _ = checkbox.accessibilityPerformPress()
        try await wait(until: 7)
        headline = "Write it down. Keep it in sight."
        windows[1].makeKeyAndOrderFront(nil)
        let fields = descendants(windows[1].contentView!).compactMap { $0 as? NSTextField }
            .filter { $0.isEditable && $0.stringValue.isEmpty }
        guard let field = fields.last else { throw NSError(domain: "MarketingCapture", code: 4) }
        try await moveCursor(to: field, duration: 0.8)
        windows[1].makeFirstResponder(field)
        guard let editor = windows[1].fieldEditor(true, for: field) as? NSTextView else {
            throw NSError(domain: "MarketingCapture", code: 5)
        }
        for character in String(localized: "Book the vet") {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            try await Swift.Task.sleep(for: .milliseconds(95))
        }
        try await Swift.Task.sleep(for: .milliseconds(350))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await wait(until: 13)
        windows[1].makeFirstResponder(nil)
        headline = "More room to focus."
        guard let minimize = windows[2].standardWindowButton(.miniaturizeButton) else {
            throw NSError(domain: "MarketingCapture", code: 6)
        }
        try await moveCursor(to: minimize, duration: 1)
        try await wait(until: 14.8)
        minimize.performClick(nil)
        compactNoteID = noteIDs[2]
        // Compact notes can be dragged anywhere. Keep this one within the
        // staging canvas instead of the real screen's configured corner.
        windows[2].setFrameOrigin(NSPoint(x: stage.frame.minX + compactEdgeMargin,
                                         y: stage.frame.minY + compactEdgeMargin))
        try await wait(until: 19)
        headline = "Done. Off your mind."
        try await moveCursor(to: CGPoint(x: 350, y: 150), duration: 0.9)
        try await wait(until: 27.5)
        headline = "Keep your next step in sight."
        cursor.orderOut(nil)
        try await wait(until: 30.2)
        try await recorder.stop()
        let payload: [String: Any] = [
            "status": "complete", "mockDataOnly": true, "cloudKitStarted": false,
            "width": 1920, "height": 1080, "fps": 30,
            "headlineScale": 1.875, "expandedNoteScale": expandedNoteScale,
            "headlinePointSize": 82.5, "subtitlePointSize": 33.75,
            "completedWindowScale": 1.15, "homeWindowScale": 0.85,
            "backgroundDocument": "native-mock-email-inbox",
            "compositionRevision": 5,
            "backgroundDocumentActivated": activatedBackgroundDocument,
            "backgroundWindowSize": ["width": backgroundDocument.frame.width, "height": backgroundDocument.frame.height],
            "backgroundWindowTitle": backgroundDocument.title,
            "backgroundWindowOrigin": ["x": backgroundDocument.frame.minX - stage.frame.minX,
                                        "y": backgroundDocument.frame.minY - stage.frame.minY],
            "blueNoteOverlapFraction": windows[1].frame.intersection(backgroundDocument.frame).width / windows[1].frame.width,
            "openingWindowSizes": openingWindowSizes,
            "openingWindowOrigins": openingWindowOrigins,
            "pendingNotesAboveBackground": windows[1].level.rawValue > backgroundDocument.level.rawValue
                && windows[2].level.rawValue > backgroundDocument.level.rawValue,
            "expandedTextPointSize": 15, "bottomLeftGatherFactor": bottomLeftGatherFactor,
            "compactEdgeMargin": compactEdgeMargin,
            "notesRemaining": store.notes.count,
            "capturedTaskPresent": store.notes.contains { $0.tasks.contains { $0.text == String(localized: "Book the vet") } }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputDirectory.appendingPathComponent("capture-result.json"))
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func demonstrateFloatingNotes() async throws {
        let origin = backgroundDocument.frame.origin
        try await moveCursor(to: CGPoint(x: backgroundDocument.frame.minX - stage.frame.minX + backgroundDocument.frame.width * 0.44,
                                        y: backgroundDocument.frame.maxY - stage.frame.minY - 16), duration: 0.65)
        backgroundDocument.makeKeyAndOrderFront(nil)
        backgroundDocument.makeFirstResponder(nil)
        activatedBackgroundDocument = backgroundDocument.isKeyWindow
        let cursorOrigin = cursor.frame.origin
        // Move the real native window and presentation cursor together. The
        // pending notes keep their production .floating window level.
        for step in 1...36 {
            let t = Double(step) / 36
            let eased = t * t * (3 - 2 * t)
            let offset = CGPoint(x: 0, y: -10 * eased)
            backgroundDocument.setFrameOrigin(CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
            cursor.setFrameOrigin(CGPoint(x: cursorOrigin.x + offset.x, y: cursorOrigin.y + offset.y))
            try await Swift.Task.sleep(for: .seconds(1.0 / 60))
        }
    }

    private func wait(until seconds: Double) async throws {
        let remaining = seconds - Date().timeIntervalSince(startTime!)
        if remaining > 0 { try await Swift.Task.sleep(for: .seconds(remaining)) }
    }

    private func moveCursor(to view: NSView, duration: Double) async throws {
        let point = view.window!.convertPoint(toScreen: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil))
        try await moveCursor(to: CGPoint(x: point.x - stage.frame.minX, y: point.y - stage.frame.minY), duration: duration)
    }

    private func moveCursor(to point: CGPoint, duration: Double) async throws {
        let origin = cursor.frame.origin
        let target = CGPoint(x: stage.frame.minX + point.x, y: stage.frame.minY + point.y - 27)
        let steps = Int(duration * 60)
        for step in 1...max(1, steps) {
            let t = Double(step) / Double(max(1, steps))
            let eased = t * t * (3 - 2 * t)
            cursor.setFrameOrigin(CGPoint(x: origin.x + (target.x - origin.x) * eased,
                                         y: origin.y + (target.y - origin.y) * eased))
            try await Swift.Task.sleep(for: .seconds(duration / Double(max(1, steps))))
        }
    }

    private func writeStatus(_ message: String) {
        try? message.write(to: outputDirectory.appendingPathComponent("capture-status.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
