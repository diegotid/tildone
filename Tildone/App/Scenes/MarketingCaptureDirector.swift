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
    private var story: String { Bundle.main.infoDictionary?["MarketingStory"] as? String ?? "desktop" }
    var isFirstScreenshot: Bool { story == "screenshot-1" }
    var isSecondScreenshot: Bool { story == "screenshot-2" }
    var isProScreenshot: Bool { story == "screenshot-3" }
    var isPrivacyScreenshot: Bool { story == "screenshot-4" }
    var isScreenshot: Bool { isFirstScreenshot || isSecondScreenshot || isProScreenshot || isPrivacyScreenshot }
    var canvasSize: CGSize { CGSize(width: 1440, height: isScreenshot ? 900 : 810) }
    var subtitle: String {
        if isFirstScreenshot { return "A clearer desktop. Your other lists still close." }
        if isSecondScreenshot { return "Your plans stay up to date, wherever you are." }
        if isPrivacyScreenshot { return "Personal reminders, discreet until you need them." }
        return isProScreenshot ? "Small steps for your plans. A place for your thoughts." : "Sticky to-dos for your Mac."
    }
    var localeIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "MarketingLocale") as? String ?? "en-US"
    }
    private var stage: NSWindow!
    private var windows: [MacNoteWindow] = []
    private var noteIDs: [NoteID] = []
    private var store: MacSharedStore!
    private var privacyNoteID: NoteID?
    private var observedBlurStates: [NoteID: Bool] = [:]
    private var trackingPrivacyMenu: NSMenu?
    private var privacyMenuOpenFailed = false
    func isPrivacyBlurredNote(_ id: NoteID) -> Bool { isPrivacyScreenshot && id == privacyNoteID }
    private(set) var phoneScreenshot: NSImage?
    private var phoneScreenshotProof: [String: Any] = [:]
    private(set) var phoneSourceSize = CGSize.zero
    private(set) var phoneCropY: CGFloat = 0
    let phoneTop: CGFloat = 232
    let phoneLeft: CGFloat = 900
    let phoneBezel: CGFloat = 12
    var phoneRenderingScale: CGFloat { (canvasSize.height - phoneTop) / max(1, phoneCropY + phoneBezel) }
    var phoneFrame: CGRect {
        CGRect(x: phoneLeft, y: phoneTop,
               width: (phoneSourceSize.width + 2 * phoneBezel) * phoneRenderingScale,
               height: (phoneSourceSize.height + 2 * phoneBezel) * phoneRenderingScale)
    }
    private var recorder = MarketingCaptureRecorder()
    private var cursor: NSWindow!
    private var backgroundDocument: NSWindow!
    private var activatedBackgroundDocument = false
    private var run: Swift.Task<Void, Never>?
    private var startTime: Date?
    var expandedNoteScale: CGFloat { isSecondScreenshot || isPrivacyScreenshot ? 1.1 : (isScreenshot ? 1 : 0.75) }
    var singleMemoFitFraction: CGFloat { isProScreenshot ? 0.95 : 0.6 }
    private let bottomLeftGatherFactor: CGFloat = 0.75
    private let compactEdgeMargin: CGFloat = 47.5
    private var outputDirectory: URL {
        URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "MarketingOutputDirectory") as! String,
            isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        run = Swift.Task {
            do {
                try await prepare()
                if isScreenshot { try await captureScreenshot() }
                else { try await record() }
            }
            catch {
                writeStatus("ERROR: \(error)")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        if let privacyNoteID { NoteFocusPrivacySettings.setBlurOverride(nil, for: privacyNoteID) }
    }

    private func prepare() async throws {
        if isFirstScreenshot { headline = "One thing at a time." }
        else if isSecondScreenshot { headline = "Pick up where you left off." }
        else if isProScreenshot { headline = "Make the big thing feel smaller." }
        else if isPrivacyScreenshot { headline = "Keep your plans to yourself." }
        UserDefaults.standard.register(defaults: [
            FontSize.storageKey: 20.0,
            TaskLineTruncation.storageKey: TaskLineTruncation.multiple.rawValue,
            NoteWindowBackground.opacityStorageKey: 0.72,
            "taskSpellCheckingEnabled": false,
            "completedWelcomeOnboarding": true,
            "seenWhatsNewContent": WhatsNewRelease.contentID
        ])
        // Process-only preferences also protect older capture app copies that
        // share the private bundle ID and rely on their registered defaults.
        var capturePreferences = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        capturePreferences[FontSize.storageKey] = isFirstScreenshot ? 24.0 : 20.0
        capturePreferences[CompactNoteScale.storageKey] = isFirstScreenshot
            ? CompactNoteScale.maximumValue : CompactNoteScale.defaultValue
        if isPrivacyScreenshot { capturePreferences[NoteWindowClickThrough.storageKey] = false }
        UserDefaults.standard.setVolatileDomain(capturePreferences, forName: UserDefaults.argumentDomain)
        if isPrivacyScreenshot {
            NotificationCenter.default.addObserver(self, selector: #selector(privacyBlurChanged(_:)),
                name: Notification.Name("TildoneMarketingBlurState"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(privacyMenuBegan(_:)),
                name: NSMenu.didBeginTrackingNotification, object: nil)
        }
        SingleMemoTypography.registerBundledFonts()
        let repository = try TildoneRepository(descriptor: .inMemory())
        store = MacSharedStore(repository: repository)
        store.setUndoEnabled(false)
        let fixture: [(String, NoteColor, [(String, Bool)], CGPoint)] = isFirstScreenshot ? [
            (String(localized: "Finish the proposal"), .yellow, [
                (String(localized: "Check the final figures"), true),
                (String(localized: "Add the summary"), false),
                (String(localized: "Send to Maya"), false)
            ], CGPoint(x: 550, y: 250)),
            (String(localized: "Home"), .blue, [
                (String(localized: "Call the electrician"), true),
                (String(localized: "Pick up the parcel"), false)
            ], CGPoint(x: 100, y: 180)),
            (String(localized: "Weekend"), .pink, [
                (String(localized: "Choose a walking route"), true),
                (String(localized: "Book a table"), false),
                (String(localized: "Pack the weekend bag"), false)
            ], CGPoint(x: 460, y: 150))
        ] : [
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
        if isSecondScreenshot {
            notes = try await makeContinuityScreenshotNotes()
        } else if isProScreenshot {
            notes = try await makeScreenshotNotes(repository: repository)
        } else if isPrivacyScreenshot {
            notes = try await makePrivacyScreenshotNotes()
        } else {
            for (title, color, tasks, _) in fixture {
                let note = try await store.createNote(color: color)
                try await store.renameNote(note.id, to: title)
                for (text, completed) in tasks {
                    let task = try await store.addTask(to: note.id, text: text)
                    if completed { _ = try await store.setTaskCompletion(task.id, completed: true) }
                }
                notes.append(store.note(note.id)!)
            }
        }
        guard let screen = NSScreen.main,
              let wallpaper = NSImage(contentsOfFile: Bundle.main.path(forResource: "GoldenGate", ofType: "png") ?? "") else {
            throw NSError(domain: "MarketingCapture", code: 2)
        }
        stage = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX - 720,
                                             y: screen.visibleFrame.midY - canvasSize.height / 2,
                                             width: canvasSize.width, height: canvasSize.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        stage.isReleasedWhenClosed = false
        stage.title = "Tildone Marketing Preview"
        stage.appearance = NSAppearance(named: .aqua)
        stage.contentView = NSHostingView(rootView: MarketingCaptureBackdrop(director: self, wallpaper: wallpaper)
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        stage.orderFront(nil)
        // Attach the screenshot's background before its floating note siblings.
        if isProScreenshot { makeBackgroundMailWindow() }
        if isPrivacyScreenshot { makeBackgroundTextEditWindow() }
        for (index, note) in notes.enumerated() {
            let windowScale: CGFloat = index == 0 ? 1.15 : (index == 1 ? 0.85 : 1)
            makeWindow(note: note, origin: isSecondScreenshot || isPrivacyScreenshot ? .zero : fixture[index].3,
                       windowScale: windowScale)
        }
        if isScreenshot {
            let frames = isFirstScreenshot ? [
                CGRect(x: 550, y: 250, width: fittedChecklistWidth(notes[0]), height: 345),
                CGRect(x: 100, y: 180, width: 330, height: 300),
                CGRect(x: 460, y: 150, width: 330, height: 300)
            ] : isSecondScreenshot ? continuityScreenshotFrames(notes) : isPrivacyScreenshot ? [
                CGRect(x: 150, y: 180, width: 380, height: 400),
                CGRect(x: 1020, y: 310, width: min(370, max(320, fittedChecklistWidth(notes[1]) * expandedNoteScale)), height: 280)
            ] : [
                CGRect(x: 190, y: 180, width: 340, height: 405),
                CGRect(x: 640, y: 130, width: 255, height: 270)
            ]
            for (window, frame) in zip(windows, frames) {
                window.setFrame(frame.offsetBy(dx: stage.frame.minX, dy: stage.frame.minY), display: true)
            }
            if isSecondScreenshot {
                // Respect any AppKit minimum-frame rounding while retaining
                // the approved small overlap and a visible bottom margin.
                let homeY = windows[0].frame.minY - windows[2].frame.height + 20
                let lift = max(0, stage.frame.minY + 24 - homeY)
                windows[0].setFrameOrigin(NSPoint(x: windows[0].frame.minX, y: windows[0].frame.minY + lift))
                windows[2].setFrameOrigin(NSPoint(x: windows[0].frame.minX + 62, y: homeY + lift))
            }
        }
        if !isScreenshot { makeBackgroundMailWindow() }
        // Move only the expanded blue and pink notes. Their compact
        // presentation keeps the established bottom-left edge margin.
        for window in isScreenshot ? [] : [windows[1], windows[2]] {
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
        if !isScreenshot { cursor.orderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        windows[isFirstScreenshot || isSecondScreenshot ? 0 : 1].makeKeyAndOrderFront(nil)
        try await Swift.Task.sleep(for: .seconds(2))
        for window in windows { window.makeFirstResponder(nil) }
        writeStatus("READY")
    }

    @objc private func privacyBlurChanged(_ notification: Notification) {
        guard let id = notification.object as? NoteID,
              let blurred = notification.userInfo?["blurred"] as? Bool else { return }
        observedBlurStates[id] = blurred
    }

    @objc private func privacyMenuBegan(_ notification: Notification) {
        trackingPrivacyMenu = notification.object as? NSMenu
    }

    private func makePrivacyScreenshotNotes() async throws -> [MacNoteSnapshot] {
        let fixture: [(String, NoteColor, [(String, Bool)])] = [
            (String(localized: "Personal"), .blue, [
                (String(localized: "Review the budget"), false),
                (String(localized: "Book the check-up"), false),
                (String(localized: "Renew the passport"), false)
            ]),
            (String(localized: "Workshop"), .yellow, [
                (String(localized: "Check the agenda"), true),
                (String(localized: "Add the examples"), false),
                (String(localized: "Send the handout"), false)
            ])
        ]
        var notes: [MacNoteSnapshot] = []
        for (title, color, items) in fixture {
            let note = try await store.createNote(color: color)
            try await store.renameNote(note.id, to: title)
            for (text, completed) in items {
                let task = try await store.addTask(to: note.id, text: text)
                if completed { _ = try await store.setTaskCompletion(task.id, completed: true) }
            }
            notes.append(store.note(note.id)!)
        }
        privacyNoteID = notes[0].id
        // Seed a presentation preference only inside the private capture app.
        // The production Note and its titlebar Menu both read this same state.
        NoteFocusPrivacySettings.setBlurOverride(true, for: notes[0].id)
        return notes
    }

    private func makeBackgroundTextEditWindow() {
        backgroundDocument = NSWindow(contentRect: NSRect(
            x: stage.frame.minX + 765, y: stage.frame.minY + 165, width: 530, height: 305),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        backgroundDocument.isReleasedWhenClosed = false
        backgroundDocument.title = String(localized: "Workshop outline")
        backgroundDocument.appearance = NSAppearance(named: .aqua)
        backgroundDocument.titlebarAppearsTransparent = true
        backgroundDocument.tabbingMode = .disallowed
        backgroundDocument.contentView = NSHostingView(rootView: MarketingCaptureTextEdit()
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        backgroundDocument.setFrame(NSRect(x: stage.frame.minX + 765, y: stage.frame.minY + 165,
                                           width: 530, height: 305), display: false)
        stage.addChildWindow(backgroundDocument, ordered: .above)
        backgroundDocument.orderFront(nil)
    }

    private func capturePrivacyScreenshot() async throws {
        cursor.orderOut(nil)
        // Keep the real pointer away from the note body so the actual native
        // hover-to-reveal rule leaves its content blurred during the still.
        let screenTop = NSScreen.screens.first?.frame.maxY ?? stage.frame.maxY
        guard CGWarpMouseCursorPosition(CGPoint(x: stage.frame.maxX - 12,
                                                y: screenTop - stage.frame.minY - 12)) == .success else {
            throw NSError(domain: "MarketingCapture", code: 25)
        }
        windows[0].makeKeyAndOrderFront(nil)
        for window in windows {
            window.makeFirstResponder(nil)
            window.order(.above, relativeTo: backgroundDocument.windowNumber)
        }
        try await Swift.Task.sleep(for: .milliseconds(500))
        guard let accessory = windows[0].noteTitlebarAccessoryController else {
            throw NSError(domain: "MarketingCapture", code: 26)
        }
        // A run-loop timer opens AppKit's tracking loop without keeping a main
        // dispatch task on the stack. Capture can then run while the menu tracks.
        let timer = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !accessory.marketingOpenPrivacyMenu() { self.privacyMenuOpenFailed = true }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        defer {
            timer.invalidate()
            trackingPrivacyMenu?.cancelTrackingWithoutAnimation()
        }
        writeStatus("OPENING NATIVE PRIVACY MENU")
        let deadline = Date().addingTimeInterval(6)
        let blurTitle = String(localized: "Blur Content")
        while trackingPrivacyMenu?.items.contains(where: { $0.title == blurTitle }) != true,
              !privacyMenuOpenFailed, Date() < deadline {
            try await Swift.Task.sleep(for: .milliseconds(50))
        }
        try await Swift.Task.sleep(for: .milliseconds(400))
        guard let menu = trackingPrivacyMenu,
              let blurItem = menu.items.first(where: { $0.title == blurTitle }), blurItem.state == .on,
              let backgroundItem = menu.items.first(where: { $0.title == String(localized: "Stay in Background") }),
              backgroundItem.state == .off,
              observedBlurStates[noteIDs[0]] == true, observedBlurStates[noteIDs[1]] == false else {
            throw NSError(domain: "MarketingCapture", code: 27,
                          userInfo: [NSLocalizedDescriptionKey: "The real privacy menu must show Blur Content enabled while the native note title and tasks are blurred."])
        }
        let notesAboveDocument = windows.allSatisfy { window in
            guard let noteIndex = NSApp.orderedWindows.firstIndex(of: window),
                  let documentIndex = NSApp.orderedWindows.firstIndex(of: backgroundDocument) else { return false }
            return noteIndex < documentIndex
        }
        guard notesAboveDocument, windows[1].frame.intersects(backgroundDocument.frame) else {
            throw NSError(domain: "MarketingCapture", code: 28)
        }
        let destination = outputDirectory.appendingPathComponent("Tildone-macOS-screenshot-04-\(localeIdentifier).png")
        let knownIDs = Set([CGWindowID(stage.windowNumber), CGWindowID(backgroundDocument.windowNumber),
                            CGWindowID(cursor.windowNumber)] + windows.map { CGWindowID($0.windowNumber) })
        writeStatus("CAPTURING")
        let popupCount = try await recorder.captureImage(windowID: CGWindowID(stage.windowNumber),
            destination: destination, width: 2880, height: 1800, auxiliaryExcludingWindowIDs: knownIDs)
        let payload: [String: Any] = [
            "status": "complete", "asset": "screenshot-4", "compositionRevision": 3,
            "locale": localeIdentifier, "preferredLocalizations": Bundle.main.preferredLocalizations,
            "mockDataOnly": true, "cloudKitStarted": false,
            "width": 2880, "height": 1800, "hasAlpha": false,
            "nativeNoteCount": 2, "nativeBackgroundDocument": "textedit",
            "nativePrivacyMenuVisible": true, "nativeMenuPopupCount": popupCount,
            "nativeMenuStateVerified": true, "nativeMenuPixelReviewRequired": true,
            "nativeMenuCaptureMethod": "stage-child-windows",
            "nativeMenuTitles": menu.items.filter { !$0.isSeparatorItem }.map(\.title),
            "blurMenuChecked": blurItem.state == .on, "backgroundMenuChecked": backgroundItem.state == .on,
            "personalNoteBlurred": observedBlurStates[noteIDs[0]] == true,
            "workshopNoteBlurred": observedBlurStates[noteIDs[1]] == true,
            "blurScope": "title-and-tasks", "nativeBlurRadius": 3,
            "notesAboveBackgroundDocument": notesAboveDocument,
            "workshopOverlapsBackgroundDocument": windows[1].frame.intersects(backgroundDocument.frame),
            "personalTaskCount": store.note(noteIDs[0])!.tasks.count,
            "workshopTaskCount": store.note(noteIDs[1])!.tasks.count,
            "workshopCompletedTaskCount": store.note(noteIDs[1])!.tasks.filter(\.isCompleted).count,
            "maxIndentLevel": 0, "singleMemoCount": 0,
            "proDisclosureVisible": true,
            "proPurchaseDisclosure": String(localized: "Tildone Pro · One-time purchase"),
            "proPurchaseModel": "one-time-non-consumable",
            "expandedContentScale": expandedNoteScale,
            "noteWindowFrames": windows.map { ["x": $0.frame.minX - stage.frame.minX,
                                                "y": $0.frame.minY - stage.frame.minY,
                                                "width": $0.frame.width, "height": $0.frame.height] },
            "file": destination.lastPathComponent
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("screenshot-result.json"))
        menu.cancelTrackingWithoutAnimation()
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
    }

    private func makeContinuityScreenshotNotes() async throws -> [MacNoteSnapshot] {
        let directory = URL(fileURLWithPath: Bundle.main.infoDictionary?["MarketingPhoneFramesDirectory"] as! String)
        let data = try Data(contentsOf: directory.appendingPathComponent("phone-screenshot-result.json"))
        phoneScreenshotProof = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard phoneScreenshotProof["asset"] as? String == "screenshot-2",
              phoneScreenshotProof["screenshotRevision"] as? Int == 3,
              phoneScreenshotProof["nativeView"] as? String == "NotesDeckView",
              phoneScreenshotProof["locale"] as? String == localeIdentifier,
              phoneScreenshotProof["bothDeckPreviewsVisible"] as? Bool == true,
              phoneScreenshotProof["softwareKeyboardHidden"] as? Bool == true,
              phoneScreenshotProof["phoneSyncIndicatorConnected"] as? Bool == true,
              let screenSize = phoneScreenshotProof["screenPointSize"] as? [Double], screenSize.count == 2,
              let cropY = phoneScreenshotProof["cropAboveSearchY"] as? Double,
              cropY > screenSize[1] * 0.75, cropY < screenSize[1],
              phoneScreenshotProof["deckContentAboveCrop"] as? Bool == true,
              let records = phoneScreenshotProof["notes"] as? [[String: Any]], records.count == 4,
              let image = NSImage(contentsOf: directory.appendingPathComponent("phone-shared.png")) else {
            throw NSError(domain: "MarketingCapture", code: 18,
                          userInfo: [NSLocalizedDescriptionKey: "The matching native iPhone decks must be captured first."])
        }
        phoneSourceSize = CGSize(width: screenSize[0], height: screenSize[1])
        // UIKit's measured field/bar bounds omit the outer glass capsule and
        // shadow. Native revision-3 captures exposed its top edge at the canvas
        // bottom; clear that chrome by 12 additional source-screen points.
        phoneCropY = cropY - 12
        guard let decks = phoneScreenshotProof["decks"] as? [[String: Any]], decks.count == 2,
              decks.allSatisfy({ deck in
                  ["titleFrame", "taskFrame"].allSatisfy { key in
                      guard let frame = deck[key] as? [Double], frame.count == 4 else { return false }
                      return frame[1] + frame[3] < phoneCropY
                  }
              }) else {
            throw NSError(domain: "MarketingCapture", code: 18,
                          userInfo: [NSLocalizedDescriptionKey: "The native deck text must remain above the full search-capsule crop."])
        }
        let fixture: [(String, NoteColor, [(String, Bool)])] = [
            (String(localized: "Dinner plans"), .yellow, [
                (String(localized: "Confirm the guests"), true),
                (String(localized: "Pick up fresh pasta"), false),
                (String(localized: "Bring dessert"), false)
            ]),
            (String(localized: "Shopping"), .yellow, [
                (String(localized: "Coffee beans"), false),
                (String(localized: "Fresh fruit"), false)
            ]),
            (String(localized: "Home"), .blue, [
                (String(localized: "Call the electrician"), true),
                (String(localized: "Pick up the parcel"), false)
            ]),
            (String(localized: "Weekend"), .blue, [
                (String(localized: "Choose a walking route"), false),
                (String(localized: "Check the train times"), false)
            ])
        ]
        var notes: [MacNoteSnapshot] = []
        for ((title, color, items), record) in zip(fixture, records) {
            guard record["title"] as? String == title, record["color"] as? String == color.rawValue,
                  record["taskTexts"] as? [String] == items.map({ $0.0 }),
                  record["completedTexts"] as? [String] == items.filter({ $0.1 }).map({ $0.0 }) else {
                throw NSError(domain: "MarketingCapture", code: 19,
                              userInfo: [NSLocalizedDescriptionKey: "The four localized note fixtures must match on both platforms."])
            }
            let note = try await store.createNote(color: color)
            try await store.renameNote(note.id, to: title)
            for (text, completed) in items {
                let task = try await store.addTask(to: note.id, text: text)
                if completed { _ = try await store.setTaskCompletion(task.id, completed: true) }
            }
            notes.append(store.note(note.id)!)
        }
        phoneScreenshot = image
        return notes
    }

    private func continuityScreenshotFrames(_ notes: [MacNoteSnapshot]) -> [CGRect] {
        // Approved scattered composition, using native note sizes. Localized
        // text can widen a note; keep the two upper notes clear of each other.
        let height = ceil(Layout.minNoteHeight * expandedNoteScale)
        let widths = notes.map { min(390, fittedChecklistWidth($0) * expandedNoteScale) }
        let dinnerX = max(430, 60 + widths[3] + 36)
        let dinner = CGRect(x: dinnerX, y: 271, width: widths[0], height: height)
        let shopping = CGRect(x: 107, y: 28, width: widths[1], height: height)
        let home = CGRect(x: dinnerX + 62, y: dinner.minY - height + 20,
                          width: widths[2], height: height)
        let weekend = CGRect(x: 60, y: 334, width: widths[3], height: height)
        return [dinner, shopping, home, weekend]
    }

    private func fittedChecklistWidth(_ note: MacNoteSnapshot) -> CGFloat {
        let taskSize = CGFloat(UserDefaults.standard.double(forKey: FontSize.storageKey))
        let titleWidth = ((note.title ?? "") as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NoteTypography.topicFontSize(for: taskSize), weight: .bold)
        ]).width
        let taskWidth = note.tasks.map { task in
            (task.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: taskSize)]).width
        }.max() ?? 0
        // Title: two 20-point margins plus native field slack. Rows also need
        // room for the checkbox and its spacing. Keep the actual text sizes.
        return ceil(max(Layout.minNoteWidth, max(titleWidth + 44, taskWidth + 72)))
    }

    private func makeScreenshotNotes(repository: TildoneRepository) async throws -> [MacNoteSnapshot] {
        let plan = try await store.createNote(color: .yellow)
        try await store.renameNote(plan.id, to: String(localized: "Seaside getaway"))
        var tasks: [TildoneDomain.Task] = []
        for text in [String(localized: "Plan the journey"), String(localized: "Receive train tickets"),
                     String(localized: "Check station directions"), String(localized: "Pack the weekend bag"),
                     String(localized: "Pick a coastal walk")] {
            tasks.append(try await store.addTask(to: plan.id, text: text))
        }
        // Seed existing Pro content in the disposable repository. Presentation
        // uses the production Note; no purchase or StoreKit state is fabricated.
        _ = try await repository.applyTaskStructureUpdates(in: plan.id, updates: [
            TaskStructureUpdate(id: tasks[1].id, indentLevel: 1),
            TaskStructureUpdate(id: tasks[2].id, indentLevel: 1)
        ])
        try await store.reload(plan.id)
        _ = try await store.setTaskCompletion(tasks[1].id, completed: true)

        let memo = try await store.createNote(color: .blue)
        _ = try await store.addTask(to: memo.id, text: String(localized: "A book, a lamp,\na little quiet."))
        _ = try await repository.setNoteKind(id: memo.id, kind: .singleTask)
        _ = try await repository.setSingleMemoFont(id: memo.id,
                                                  font: localeIdentifier == "zh-Hans" ? .pingFangSC : .overlock)
        try await store.reload(memo.id)
        guard let checklist = store.note(plan.id), let singleMemo = store.note(memo.id) else {
            throw NSError(domain: "MarketingCapture", code: 14)
        }
        return [checklist, singleMemo]
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
        let host = NSHostingView(rootView: MarketingCaptureMail()
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        host.sizingOptions = []
        backgroundDocument.contentView = host
        let frame = isScreenshot
            ? NSRect(x: stage.frame.minX + 800, y: stage.frame.minY + 240,
                     width: 490, height: 355)
            : NSRect(x: windows[1].frame.midX + 195, y: windows[1].frame.minY,
                     width: 390 * 1.25, height: 308 * 1.25)
        backgroundDocument.setFrame(frame, display: false)
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
        ).environment(\.locale, Locale(identifier: localeIdentifier))))
        let privacyState = NoteFocusPrivacySettings.state(for: note.id, focusBlurred: false, focusAllowsBackground: false)
        let accessory = MacNoteTitlebarAccessoryController(
            colorPicker: NoteColorPickerTitlebarControl(store: store, presentation: presentation, noteID: note.id),
            syncIndicatorState: .hidden, store: store, presentation: presentation, noteID: note.id,
            focusPrivacy: isPrivacyScreenshot ? privacyState : nil)
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

    private func captureScreenshot() async throws {
        if isPrivacyScreenshot {
            try await capturePrivacyScreenshot()
            return
        }
        if isSecondScreenshot {
            try await captureContinuityScreenshot()
            return
        }
        if isFirstScreenshot {
            try await captureFirstScreenshot()
            return
        }
        cursor.orderOut(nil)
        // A simple hierarchy and a single memo, using the production windows
        // and controls. No typing, fading or transient UI in the still image.
        // Activating a child with makeKeyAndOrderFront also raises it over its
        // siblings. Keep Mail's existing position and explicitly order the notes
        // above it; the stage's child hierarchy is part of the captured image.
        backgroundDocument.makeKey()
        for window in windows {
            window.order(.above, relativeTo: backgroundDocument.windowNumber)
        }
        for window in windows { window.makeFirstResponder(nil) }
        try await Swift.Task.sleep(for: .seconds(1))
        stage.contentView?.layoutSubtreeIfNeeded()
        for window in windows { window.contentView?.layoutSubtreeIfNeeded() }
        let notesAboveMail = windows.allSatisfy { window in
            guard let noteIndex = NSApp.orderedWindows.firstIndex(of: window),
                  let mailIndex = NSApp.orderedWindows.firstIndex(of: backgroundDocument) else { return false }
            return noteIndex < mailIndex
        }
        guard backgroundDocument.isKeyWindow, notesAboveMail else {
            throw NSError(domain: "MarketingCapture", code: 15,
                          userInfo: [NSLocalizedDescriptionKey: "The floating notes must be above the active Mail window before capture."])
        }
        let destination = outputDirectory.appendingPathComponent("Tildone-macOS-screenshot-03-\(localeIdentifier).png")
        writeStatus("CAPTURING")
        try await recorder.captureImage(windowID: CGWindowID(stage.windowNumber), destination: destination,
                                        width: 2880, height: 1800)
        let payload: [String: Any] = [
            "status": "complete", "asset": "screenshot-3", "locale": localeIdentifier,
            "preferredLocalizations": Bundle.main.preferredLocalizations,
            "mockDataOnly": true, "cloudKitStarted": false,
            "width": 2880, "height": 1800, "hasAlpha": false,
            "nativeNoteCount": windows.count, "expandedContentScale": expandedNoteScale,
            "compositionRevision": 7, "nativeBackgroundDocument": "mail",
            "singleMemoFitFraction": singleMemoFitFraction,
            "backgroundDocumentIsKey": backgroundDocument.isKeyWindow,
            "notesAboveBackgroundDocument": notesAboveMail,
            "memoOverlapsBackgroundDocument": windows[1].frame.intersects(backgroundDocument.frame),
            "backgroundDocumentFrame": ["x": backgroundDocument.frame.minX - stage.frame.minX,
                                         "y": backgroundDocument.frame.minY - stage.frame.minY,
                                         "width": backgroundDocument.frame.width,
                                         "height": backgroundDocument.frame.height],
            "subtaskCount": store.notes.flatMap(\.tasks).filter { $0.indentLevel > 0 }.count,
            "maxIndentLevel": store.notes.flatMap(\.tasks).map(\.indentLevel).max() ?? 0,
            "singleMemoCount": store.notes.filter { $0.kind == .singleTask }.count,
            "proDisclosureVisible": true,
            "proPurchaseDisclosure": String(localized: "Tildone Pro · One-time purchase"),
            "proPurchaseModel": "one-time-non-consumable",
            "canvasPointSize": ["width": canvasSize.width, "height": canvasSize.height],
            "noteWindowFrames": windows.map { ["x": $0.frame.minX - stage.frame.minX,
                                                "y": $0.frame.minY - stage.frame.minY,
                                                "width": $0.frame.width, "height": $0.frame.height] },
            "file": destination.lastPathComponent
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("screenshot-result.json"))
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
    }

    private func captureContinuityScreenshot() async throws {
        cursor.orderOut(nil)
        // Home stays above Dinner plans, including after native activation.
        windows[2].makeKeyAndOrderFront(nil)
        windows[2].order(.above, relativeTo: windows[0].windowNumber)
        for window in windows {
            window.makeFirstResponder(nil)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        try await Swift.Task.sleep(for: .seconds(1))
        stage.contentView?.layoutSubtreeIfNeeded()
        let notes = noteIDs.compactMap { store.note($0) }
        let records = phoneScreenshotProof["notes"] as? [[String: Any]] ?? []
        let matches = notes.count == 4 && records.count == 4 && zip(notes, records).allSatisfy { note, record in
            note.title == record["title"] as? String && note.color.rawValue == record["color"] as? String
                && note.tasks.map(\.text) == record["taskTexts"] as? [String]
                && note.tasks.filter(\.isCompleted).map(\.text) == record["completedTexts"] as? [String]
        }
        let overlap = windows[2].frame.intersection(windows[0].frame)
        let orderedWindows = NSApp.orderedWindows
        let homeAboveDinner = (orderedWindows.firstIndex(of: windows[2]) ?? Int.max)
            < (orderedWindows.firstIndex(of: windows[0]) ?? -1)
        let cropInCanvas = phoneTop + (phoneBezel + phoneCropY) * phoneRenderingScale
        let framingMatches = overlap.height >= 18 && overlap.height <= 22 && overlap.width > 0
            && homeAboveDinner && abs(cropInCanvas - canvasSize.height) < 0.01
            && phoneFrame.maxY > canvasSize.height && phoneFrame.maxX < canvasSize.width
        guard matches, phoneScreenshot != nil, framingMatches else {
            throw NSError(domain: "MarketingCapture", code: 19)
        }
        let destination = outputDirectory.appendingPathComponent("Tildone-macOS-screenshot-02-\(localeIdentifier).png")
        writeStatus("CAPTURING")
        try await recorder.captureImage(windowID: CGWindowID(stage.windowNumber), destination: destination,
                                        width: 2880, height: 1800)
        let payload: [String: Any] = [
            "status": "complete", "asset": "screenshot-2", "compositionRevision": 4,
            "locale": localeIdentifier, "preferredLocalizations": Bundle.main.preferredLocalizations,
            "mockDataOnly": true, "cloudKitStarted": false,
            "width": 2880, "height": 1800, "hasAlpha": false,
            "nativeNoteCount": notes.count, "nativePhoneView": "NotesDeckView", "phoneTaskStateMatches": matches,
            "colorCounts": ["yellow": 2, "blue": 2], "phoneDeckCount": phoneScreenshotProof["deckCount"] as? Int ?? 0,
            "bothDeckPreviewsVisible": phoneScreenshotProof["bothDeckPreviewsVisible"] as? Bool ?? false,
            "nativePhoneTitleVisible": phoneScreenshotProof["nativeTitleVisible"] as? Bool ?? false,
            "softwareKeyboardHidden": phoneScreenshotProof["softwareKeyboardHidden"] as? Bool ?? false,
            "phoneSyncIndicatorConnected": phoneScreenshotProof["phoneSyncIndicatorConnected"] as? Bool ?? false,
            "totalTaskCount": notes.reduce(0) { $0 + $1.tasks.count },
            "completedTaskCount": notes.reduce(0) { $0 + $1.tasks.filter(\.isCompleted).count },
            "nativeBackgroundDocument": "none", "proDisclosureVisible": false,
            "maxIndentLevel": notes.flatMap(\.tasks).map(\.indentLevel).max() ?? 0, "singleMemoCount": 0,
            "expandedNoteScale": expandedNoteScale,
            "scatteredNoteLayout": true, "homeAboveDinner": homeAboveDinner,
            "homeDinnerOverlapHeight": overlap.height,
            "iCloudPillBelowSubtitle": true, "phoneSearchBoxOutsideCanvas": true,
            "phoneTop": phoneTop, "phoneLeft": phoneLeft, "phoneRenderingScale": phoneRenderingScale,
            "phoneCropY": phoneCropY, "phoneScreenPointSize": [phoneSourceSize.width, phoneSourceSize.height],
            "phoneSearchChromeClearance": 12,
            "phoneFrame": [phoneFrame.minX, phoneFrame.minY, phoneFrame.width, phoneFrame.height],
            "noteWindowFrames": windows.map { ["x": $0.frame.minX - stage.frame.minX,
                                                "y": $0.frame.minY - stage.frame.minY,
                                                "width": $0.frame.width, "height": $0.frame.height] },
            "file": destination.lastPathComponent
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("screenshot-result.json"))
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
    }

    private func captureFirstScreenshot() async throws {
        cursor.orderOut(nil)
        // Use the same minimize controls as a customer. This renders the native
        // compact notes, including their titles, progress and restore control.
        for index in 1...2 {
            guard let minimize = windows[index].standardWindowButton(.miniaturizeButton),
                  minimize.isEnabled else {
                throw NSError(domain: "MarketingCapture", code: 16,
                              userInfo: [NSLocalizedDescriptionKey: "The native minimize control is unavailable."])
            }
            minimize.performClick(nil)
        }
        try await Swift.Task.sleep(for: .milliseconds(350))
        for (window, x) in zip(windows.dropFirst(), [72.0, 246.0]) {
            // Compact notes are freely movable. Place them at the staging
            // desktop's edge rather than at the real display's edge.
            window.setFrameOrigin(NSPoint(x: stage.frame.minX + x, y: stage.frame.minY + 72))
        }
        windows[0].makeKeyAndOrderFront(nil)
        for window in windows { window.makeFirstResponder(nil) }
        try await Swift.Task.sleep(for: .seconds(1))
        stage.contentView?.layoutSubtreeIfNeeded()
        for window in windows { window.contentView?.layoutSubtreeIfNeeded() }
        let compactSize = CompactNoteScale.contentSize()
        let minimized = windows.filter { $0.title.hasPrefix("_") && !$0.isMiniaturized }
        guard minimized.count == 2,
              minimized.allSatisfy({ abs($0.frame.width - compactSize.width) < 2
                  && abs($0.frame.height - compactSize.height) < 2 }),
              let mainNote = store.note(noteIDs[0]) else {
            throw NSError(domain: "MarketingCapture", code: 17,
                          userInfo: [NSLocalizedDescriptionKey: "Two native compact notes must be visible before capture."])
        }
        let destination = outputDirectory.appendingPathComponent("Tildone-macOS-screenshot-01-\(localeIdentifier).png")
        writeStatus("CAPTURING")
        try await recorder.captureImage(windowID: CGWindowID(stage.windowNumber), destination: destination,
                                        width: 2880, height: 1800)
        let payload: [String: Any] = [
            "status": "complete", "asset": "screenshot-1", "locale": localeIdentifier,
            "preferredLocalizations": Bundle.main.preferredLocalizations,
            "mockDataOnly": true, "cloudKitStarted": false,
            "width": 2880, "height": 1800, "hasAlpha": false,
            "compositionRevision": 2, "nativeBackgroundDocument": "none",
            "nativeNoteCount": windows.count, "expandedNoteCount": windows.count - minimized.count,
            "minimizedNoteCount": minimized.count, "compactNoteScale": CompactNoteScale.currentValue,
            "mainTaskCount": mainNote.tasks.count,
            "mainCompletedTaskCount": mainNote.tasks.filter(\.isCompleted).count,
            "expandedTextPointSize": UserDefaults.standard.double(forKey: FontSize.storageKey),
            "maxIndentLevel": store.notes.flatMap(\.tasks).map(\.indentLevel).max() ?? 0,
            "singleMemoCount": store.notes.filter { $0.kind == .singleTask }.count,
            "proDisclosureVisible": false,
            "canvasPointSize": ["width": canvasSize.width, "height": canvasSize.height],
            "noteWindowFrames": windows.map { ["x": $0.frame.minX - stage.frame.minX,
                                                "y": $0.frame.minY - stage.frame.minY,
                                                "width": $0.frame.width, "height": $0.frame.height] },
            "file": destination.lastPathComponent
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("screenshot-result.json"))
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
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
            "locale": localeIdentifier,
            "preferredLocalizations": Bundle.main.preferredLocalizations,
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
