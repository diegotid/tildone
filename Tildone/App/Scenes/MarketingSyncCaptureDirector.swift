#if MARKETING_CAPTURE
import AppKit
import AVFoundation
import SwiftUI
import TildoneDomain
import TildonePersistence

/// Two disposable replicas demonstrate real domain merges, never live CloudKit.
@available(macOS 15, *)
@MainActor
final class MarketingSyncCaptureDirector: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var headline = "Pick up where you left off."
    @Published var subtitle = "One less thing to keep in your head."
    @Published var eventLabel = "On your iPhone"
    @Published var eventSymbol = "iphone"
    let phonePlayer = AVPlayer()
    @Published var flowSymbol: String?
    let phoneCenter = CGPoint(x: 1173, y: 447.5)
    let cloudCenter = CGPoint(x: 1173, y: 720)
    let cloudSize = CGSize(width: 48, height: 32)
    private var sharedNoteBottom: CGFloat { 810 - cloudCenter.y - cloudSize.height / 2 }
    private var stage: NSWindow!
    private var windows: [MacNoteWindow] = []
    private var cursor: NSWindow!
    private var macRepository: TildoneRepository!
    private var phoneRepository: TildoneRepository!
    private var store: MacSharedStore!
    private var phoneStore: MacSharedStore!
    private var sharedNoteID: NoteID!
    private var completedTaskID: TaskID!
    private let recorder = MarketingCaptureRecorder()
    private var run: Swift.Task<Void, Never>?
    private var startTime: Date?
    private var localeIdentifier: String {
        Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US"
    }
    private var outputDirectory: URL {
        URL(fileURLWithPath: Bundle.main.infoDictionary?["MarketingOutputDirectory"] as! String,
            isDirectory: true)
    }
    private var phoneDirectory: URL {
        URL(fileURLWithPath: Bundle.main.infoDictionary?["MarketingPhoneFramesDirectory"] as! String,
            isDirectory: true)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        run = Swift.Task {
            do { try await prepare(); try await record() }
            catch { writeStatus("ERROR: \(error)"); NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func prepare() async throws {
        let phoneVideo = phoneDirectory.appendingPathComponent("phone-native.mp4")
        guard FileManager.default.fileExists(atPath: phoneVideo.path) else {
            throw NSError(domain: "MarketingSyncCapture", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Record the native iPhone story before recording the Mac scene."])
        }
        phonePlayer.replaceCurrentItem(with: AVPlayerItem(url: phoneVideo))
        phonePlayer.isMuted = true
        phonePlayer.actionAtItemEnd = .pause
        UserDefaults.standard.register(defaults: [
            FontSize.storageKey: 20.0,
            TaskLineTruncation.storageKey: TaskLineTruncation.multiple.rawValue,
            NoteWindowBackground.opacityStorageKey: 0.72,
            "taskSpellCheckingEnabled": false,
            "completedWelcomeOnboarding": true,
            "seenWhatsNewContent": WhatsNewRelease.contentID
        ])
        // A supported Mac setting, scoped to the private capture bundle. Keep
        // the first task in place so its completed state matches iPhone.
        UserDefaults.standard.set(false, forKey: AppAppearance.moveCheckedTasksToEndStorageKey)
        SingleMemoTypography.registerBundledFonts()
        macRepository = try TildoneRepository(descriptor: .inMemory())
        phoneRepository = try TildoneRepository(descriptor: .inMemory())
        store = MacSharedStore(repository: macRepository)
        phoneStore = MacSharedStore(repository: phoneRepository)
        store.setUndoEnabled(false)
        phoneStore.setUndoEnabled(false)
        let home = try await store.createNote(color: .blue)
        try await store.renameNote(home.id, to: String(localized: "Home"))
        for text in [String(localized: "Call the electrician"), String(localized: "Pick up the parcel")] {
            _ = try await store.addTask(to: home.id, text: text)
        }
        // Both devices begin with the same one existing note. The new note
        // is created later on the phone side, after its visible capture flow.
        try await transfer(from: macRepository, to: phoneRepository)
        try await phoneStore.reloadAfterRemoteChange()

        guard let screen = NSScreen.main,
              let wallpaper = NSImage(contentsOfFile: Bundle.main.path(forResource: "GoldenGate", ofType: "png") ?? "") else {
            throw NSError(domain: "MarketingSyncCapture", code: 1)
        }
        stage = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX - 720,
                                             y: screen.visibleFrame.midY - 405,
                                             width: 1440, height: 810),
                         styleMask: .borderless, backing: .buffered, defer: false)
        stage.isReleasedWhenClosed = false
        stage.title = "Tildone Sync Marketing Preview"
        stage.appearance = NSAppearance(named: .aqua)
        stage.contentView = NSHostingView(rootView: MarketingSyncCaptureBackdrop(director: self, wallpaper: wallpaper)
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        stage.orderFront(nil)
        _ = makeWindow(noteID: home.id, frame: NSRect(x: 118, y: 125, width: 235, height: 215))
        cursor = NSWindow(contentRect: NSRect(x: stage.frame.minX + 420, y: stage.frame.minY + 110,
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
        cursor.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        stage.makeKeyAndOrderFront(nil)
        try await Swift.Task.sleep(for: .seconds(2))
        for window in windows { window.makeFirstResponder(nil) }
        let ready = await withCheckedContinuation { continuation in
            phonePlayer.preroll(atRate: 1) { continuation.resume(returning: $0) }
        }
        guard ready else { throw NSError(domain: "MarketingSyncCapture", code: 7) }
        writeStatus("READY")
    }

    private func makeWindow(noteID: NoteID, frame: NSRect) -> MacNoteWindow {
        let note = store.note(noteID)!
        let presentation = store.presentation(for: noteID)!
        let window = MacNoteWindow(contentRect: NSRect(x: stage.frame.minX + frame.minX,
                                                      y: stage.frame.minY + frame.minY,
                                                      width: frame.width, height: frame.height),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless],
                                   backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setNoteStyle(noteColor: note.color)
        window.contentMinSize = NSSize(width: Layout.minNoteWidth * 0.75, height: Layout.minNoteHeight * 0.75)
        window.title = note.legacyWindowKey
        window.titleVisibility = .hidden
        window.setNoteHostingContentView(NSHostingView(rootView: MarketingSyncCaptureNote(
            store: store, presentation: presentation, noteID: noteID
        ).environment(\.locale, Locale(identifier: localeIdentifier))))
        window.addTitlebarAccessoryViewController(MacNoteTitlebarAccessoryController(
            colorPicker: NoteColorPickerTitlebarControl(store: store, presentation: presentation, noteID: noteID),
            syncIndicatorState: .hidden, store: store, presentation: presentation, noteID: noteID))
        window.applyNoteBackgroundColor(note.color.nsColor, alpha: 0.72)
        window.setFrame(NSRect(x: stage.frame.minX + frame.minX, y: stage.frame.minY + frame.minY,
                               width: frame.width, height: frame.height), display: false)
        stage.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        windows.append(window)
        return window
    }

    private func transfer(from source: TildoneRepository, to destination: TildoneRepository) async throws {
        for note in try await source.allSyncNotes() { _ = try await destination.mergeRemoteNote(note, at: Date()) }
        for task in try await source.allSyncTasks() { _ = try await destination.mergeRemoteTask(task, at: Date()) }
    }

    private func record() async throws {
        let raw = outputDirectory.appendingPathComponent("Tildone-macOS-preview-raw.mp4")
        try? FileManager.default.removeItem(at: raw)
        let openingNoteCount = store.notes.count
        let openingWindowCount = windows.count
        try await recorder.start(windowID: CGWindowID(stage.windowNumber), destination: raw)
        startTime = Date()
        phonePlayer.play()
        writeStatus("RECORDING")
        // The native phone video starts on Notes, creates a note, then types
        // its title and first task. Let that finish before receiving it here.
        try await wait(until: 10.5)
        let newNote = try await phoneStore.createNote(color: .pink)
        sharedNoteID = newNote.id
        try await phoneStore.renameNote(newNote.id, to: String(localized: "Weekend"))
        completedTaskID = try await phoneStore.addTask(to: newNote.id, text: String(localized: "Book a table")).id
        try await wait(until: 12)
        try await transfer(from: phoneRepository, to: macRepository)
        try await store.reloadAfterRemoteChange()
        let shared = makeWindow(noteID: sharedNoteID, frame: NSRect(x: 500, y: sharedNoteBottom, width: 335, height: 340))
        shared.makeFirstResponder(nil)
        subtitle = "Your next step is already waiting."
        eventLabel = "Ready on your Mac"
        eventSymbol = "desktopcomputer"
        flowSymbol = "arrow.left"
        let noteArrived = store.note(sharedNoteID)?.tasks.map(\.text) == [String(localized: "Book a table")]
        try await wait(until: 14)
        eventLabel = "On your Mac"
        flowSymbol = "arrow.right"
        shared.makeKeyAndOrderFront(nil)
        guard let field = descendants(shared.contentView!).compactMap({ $0 as? NSTextField })
            .last(where: { $0.isEditable && $0.stringValue.isEmpty }) else {
            throw NSError(domain: "MarketingSyncCapture", code: 2)
        }
        cursor.orderFront(nil)
        try await moveCursor(to: field, duration: 0.9)
        shared.makeFirstResponder(field)
        guard let editor = shared.fieldEditor(true, for: field) as? NSTextView else {
            throw NSError(domain: "MarketingSyncCapture", code: 3)
        }
        let capturedText = String(localized: "Check the train times")
        for character in capturedText {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            try await Swift.Task.sleep(for: .milliseconds(85))
        }
        try await Swift.Task.sleep(for: .milliseconds(350))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        try await wait(until: 18.4)
        shared.makeFirstResponder(nil)
        let newTaskSaved = store.note(sharedNoteID)!.tasks.contains { $0.text == capturedText }
        let checkboxes = descendants(shared.contentView!).compactMap { $0 as? Checkbox.ClickControl }
            .filter { $0.isEnabled && !$0.isChecked }
            .sorted { $0.convert(.zero, to: nil).y > $1.convert(.zero, to: nil).y }
        guard checkboxes.count == 2 else { throw NSError(domain: "MarketingSyncCapture", code: 5) }
        try await wait(until: 19.2)
        try await moveCursor(to: checkboxes[0], duration: 0.6)
        try await wait(until: 20)
        _ = checkboxes[0].accessibilityPerformPress()
        try await wait(until: 20.8)
        cursor.orderOut(nil)
        let completedOnMac = store.note(sharedNoteID)!.tasks.contains { $0.id == completedTaskID && $0.isCompleted }
        guard newTaskSaved && completedOnMac else { throw NSError(domain: "MarketingSyncCapture", code: 6) }
        try await wait(until: 22)
        try await transfer(from: macRepository, to: phoneRepository)
        try await phoneStore.reloadAfterRemoteChange()
        let completedOnPhone = phoneStore.note(sharedNoteID)!.tasks.contains { $0.id == completedTaskID && $0.isCompleted }
        let newTaskOnPhone = phoneStore.note(sharedNoteID)!.tasks.contains { $0.text == capturedText }
        try await wait(until: 23)
        eventLabel = "Ready on your iPhone"
        eventSymbol = "iphone"
        try await wait(until: 26)
        subtitle = "Less to remember. More room for your day."
        eventLabel = "Mac and iPhone"
        eventSymbol = "icloud"
        try await wait(until: 30.2)
        phonePlayer.pause()
        try await recorder.stop()
        let phoneVerification = try JSONSerialization.jsonObject(with: Data(contentsOf:
            phoneDirectory.appendingPathComponent("phone-capture-verification.json"))) as! [String: Any]
        let phoneStates = phoneVerification["states"] as! [[String: Any]]
        let finalPhone = phoneStates.last!
        let finalMacTasks = store.note(sharedNoteID)!.tasks
        let phoneMatchesMac = finalPhone["taskTexts"] as? [String] == finalMacTasks.map(\.text)
            && finalPhone["completedTexts"] as? [String] == finalMacTasks.filter(\.isCompleted).map(\.text)
        let openingPhone = phoneStates.first!
        let payload: [String: Any] = [
            "status": "complete", "story": "sync", "compositionRevision": 7,
            "mockDataOnly": true, "cloudKitStarted": false,
            "locale": localeIdentifier, "preferredLocalizations": Bundle.main.preferredLocalizations,
            "width": 1920, "height": 1080, "fps": 30,
            "openingNoteCount": openingNoteCount, "openingWindowCount": openingWindowCount,
            "notesRemaining": store.notes.count, "replicaCount": 2,
            "remoteNoteArrived": noteArrived,
            "macTaskAdded": newTaskSaved, "macCompletionDeliveredToPhone": completedOnPhone,
            "macTaskDeliveredToPhone": newTaskOnPhone,
            "transport": "scripted-in-memory-domain-merge", "capturedTaskPresent": newTaskSaved,
            "nativePhoneUI": phoneVerification["nativeUI"] as! Bool,
            "nativePhoneVideo": phoneVerification["nativeVideo"] as! Bool,
            "phoneStartsOnNoteList": openingPhone["nativeView"] as? String == "NotesListView",
            "phoneOpeningNoteCount": openingPhone["noteCount"] as! Int,
            "phoneCreatedNote": phoneStates.map { $0["frame"] as! String }.contains("created"),
            "phoneMatchesMac": phoneMatchesMac,
            "phonePlayerReachedEndScene": phonePlayer.currentTime().seconds >= 26,
            "softwareKeyboardHidden": phoneVerification["softwareKeyboardHidden"] as? Bool == true,
            "nativeTitleVisible": phoneVerification["nativeTitleVisible"] as? Bool == true,
            "phoneSyncIndicatorConnected": phoneVerification["phoneSyncIndicatorConnected"] as? Bool == true,
            "pinkNoteBottom": shared.frame.minY - stage.frame.minY,
            "cloudSymbolBottom": sharedNoteBottom,
            "arrowVisibleAtEnd": flowSymbol == "arrow.right"
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("capture-result.json"))
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

    private func wait(until seconds: Double) async throws {
        let remaining = seconds - Date().timeIntervalSince(startTime!)
        if remaining > 0 { try await Swift.Task.sleep(for: .seconds(remaining)) }
    }

    private func moveCursor(to view: NSView, duration: Double) async throws {
        let point = view.window!.convertPoint(toScreen: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil))
        let origin = cursor.frame.origin
        let target = CGPoint(x: point.x, y: point.y - 27)
        let steps = max(1, Int(duration * 60))
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = t * t * (3 - 2 * t)
            cursor.setFrameOrigin(CGPoint(x: origin.x + (target.x - origin.x) * eased,
                                         y: origin.y + (target.y - origin.y) * eased))
            try await Swift.Task.sleep(for: .seconds(duration / Double(steps)))
        }
    }

    private func writeStatus(_ message: String) {
        try? message.write(to: outputDirectory.appendingPathComponent("capture-status.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
