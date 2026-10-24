#if MARKETING_CAPTURE
import AppKit
import SwiftUI
import TildoneDomain
import TildonePersistence

/// Screenshot five uses only disposable native windows and an in-memory store.
@available(macOS 15, *)
@MainActor
final class MarketingGatherCaptureDirector: NSObject, NSApplicationDelegate, ObservableObject {
    let canvasSize = CGSize(width: 1440, height: 900)
    let insetFrame = CGRect(x: 665, y: 90, width: 730, height: 490)
    let beforeDocumentFrame = CGRect(x: 95, y: 250, width: 310, height: 220)
    let afterDocumentFrame = CGRect(x: 895, y: 180, width: 450, height: 350)
    let contentScale: CGFloat = 0.75
    let ghostOpacity = 0.065
    let trailOpacity = 0.025
    let colors: [NoteColor] = [.blue, .yellow, .pink]
    @Published private(set) var ghostFrames: [CGRect] = []
    @Published private(set) var gatheredFrames: [CGRect] = []
    @Published private(set) var freezeChevron = false
    private var stage: NSWindow!
    private var effects: NSWindow!
    private var documents: [NSWindow] = []
    private var windows: [MacNoteWindow] = []
    private var noteIDs: [NoteID] = []
    private var store: MacSharedStore!
    private var run: Swift.Task<Void, Never>?
    private let recorder = MarketingCaptureRecorder()
    var localeIdentifier: String { Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US" }
    private var outputDirectory: URL {
        URL(fileURLWithPath: Bundle.main.infoDictionary?["MarketingOutputDirectory"] as! String, isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        run = Swift.Task {
            do { try await prepare(); try await capture() }
            catch { writeStatus("ERROR: \(error)"); NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func prepare() async throws {
        var preferences = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        preferences[FontSize.storageKey] = 20.0
        preferences[TaskLineTruncation.storageKey] = TaskLineTruncation.multiple.rawValue
        preferences[NoteWindowBackground.opacityStorageKey] = 0.72
        preferences[NoteWindowClickThrough.storageKey] = false
        preferences["taskSpellCheckingEnabled"] = false
        preferences["completedWelcomeOnboarding"] = true
        preferences["seenWhatsNewContent"] = WhatsNewRelease.contentID
        UserDefaults.standard.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
        let repository = try TildoneRepository(descriptor: .inMemory())
        store = MacSharedStore(repository: repository)
        store.setUndoEnabled(false)
        guard let screen = NSScreen.main,
              let wallpaper = NSImage(contentsOfFile: Bundle.main.path(forResource: "GoldenGate", ofType: "png") ?? "") else {
            throw NSError(domain: "MarketingGatherCapture", code: 1)
        }
        stage = NSWindow(contentRect: CGRect(x: screen.visibleFrame.midX - 720,
            y: screen.visibleFrame.midY - 450, width: 1440, height: 900),
            styleMask: .borderless, backing: .buffered, defer: false)
        stage.isReleasedWhenClosed = false
        stage.appearance = NSAppearance(named: .aqua)
        stage.contentView = NSHostingView(rootView: MarketingGatherCaptureBackdrop(director: self, wallpaper: wallpaper)
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        stage.orderFront(nil)
        makeDocument(frame: beforeDocumentFrame, scale: 0.7)
        makeDocument(frame: afterDocumentFrame, scale: 1)
        effects = NSWindow(contentRect: screenFrame(insetFrame), styleMask: .borderless, backing: .buffered, defer: false)
        effects.isReleasedWhenClosed = false
        effects.isOpaque = false
        effects.backgroundColor = .clear
        effects.hasShadow = false
        effects.ignoresMouseEvents = true
        effects.contentView = NSHostingView(rootView: MarketingGatherCaptureEffects(director: self)
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        stage.addChildWindow(effects, ordered: .above)
        effects.orderFront(nil)
        let fixtures: [(String, [String])] = [
            (String(localized: "Home"), [String(localized: "Book the repair"), String(localized: "Collect the parcel")]),
            (String(localized: "Shopping"), [String(localized: "Coffee beans"), String(localized: "Fresh fruit")]),
            (String(localized: "Weekend"), [String(localized: "Choose a walk"), String(localized: "Check train times")])
        ]
        let before = [CGRect(x: 65, y: 165, width: 230, height: 180),
                      CGRect(x: 335, y: 320, width: 240, height: 180),
                      CGRect(x: 315, y: 115, width: 235, height: 180)]
        let after = [CGRect(x: 685, y: 130, width: 230, height: 180),
                     CGRect(x: 735, y: 145, width: 240, height: 180),
                     CGRect(x: 710, y: 115, width: 235, height: 180)]
        for scene in 0..<2 {
            for index in fixtures.indices {
                let note = try await store.createNote(color: colors[index])
                try await store.renameNote(note.id, to: fixtures[index].0)
                for text in fixtures[index].1 { _ = try await store.addTask(to: note.id, text: text) }
                makeNote(store.note(note.id)!, frame: scene == 0 ? before[index] : after[index])
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        documents[1].makeKey()
        try await Swift.Task.sleep(for: .seconds(2))
        // SwiftUI/AppKit have finished attaching and enforcing their minima.
        // Set the approved frames again and derive ghosts from actual windows.
        for (index, frame) in (before + after).enumerated() {
            windows[index].setFrame(screenFrame(frame), display: true)
            windows[index].makeFirstResponder(nil)
        }
        for document in documents { document.contentView?.layoutSubtreeIfNeeded() }
        effects.order(.above, relativeTo: documents[1].windowNumber)
        for window in windows { window.order(.above, relativeTo: effects.windowNumber) }
        // Preserve the approved blue/yellow/pink stacking order explicitly.
        for scene in 0..<2 {
            windows[scene * 3 + 1].order(.above, relativeTo: windows[scene * 3].windowNumber)
            windows[scene * 3 + 2].order(.above, relativeTo: windows[scene * 3 + 1].windowNumber)
        }
        let sourceDocument = relativeFrame(documents[0])
        let outcomeDocument = relativeFrame(documents[1])
        ghostFrames = windows.prefix(3).map { window in
            let source = relativeFrame(window)
            return CGRect(x: outcomeDocument.minX + (source.minX - sourceDocument.minX) * outcomeDocument.width / sourceDocument.width,
                y: outcomeDocument.minY + (source.minY - sourceDocument.minY) * outcomeDocument.height / sourceDocument.height,
                width: source.width * outcomeDocument.width / sourceDocument.width,
                height: source.height * outcomeDocument.height / sourceDocument.height)
        }
        gatheredFrames = windows.suffix(3).map(relativeFrame)
        // The production convergence interpolator preserves expanded dimensions.
        // Its presentation targets retain the reviewed relative spatial order.
        let notes = Array(noteIDs.suffix(3))
        var starts: [NoteID: CGRect] = [:]
        var targets: [NoteID: CGRect] = [:]
        for (index, noteID) in notes.enumerated() {
            var source = ghostFrames[index]
            source.size = gatheredFrames[index].size
            starts[noteID] = source
            targets[noteID] = gatheredFrames[index]
        }
        var convergence = NoteCornerConvergence(startFrames: starts, targetFrames: targets)
        let finalFrames = convergence.frames(afterWheelDelta: -1)
        guard finalFrames.count == 3 else { throw NSError(domain: "MarketingGatherCapture", code: 2) }
        for (window, noteID) in zip(windows.suffix(3), notes) {
            window.setFrame(screenFrame(finalFrames[noteID]!), display: true)
        }
        gatheredFrames = windows.suffix(3).map(relativeFrame)
        // Use the same supported alpha adjustment as the app's dimming action.
        for window in windows.suffix(3) { window.alphaValue = NoteWindowOpacity.adjustedAlpha(1, by: -0.1) }
        freezeChevron = true
        writeStatus("READY")
    }

    private func makeDocument(frame: CGRect, scale: CGFloat) {
        let window = NSWindow(contentRect: screenFrame(frame), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = String(localized: "Workshop outline")
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        let contentHeight = frame.height - 28
        window.contentView = NSHostingView(rootView: MarketingCaptureTextEdit()
            .frame(width: frame.width / scale, height: contentHeight / scale)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: frame.width, height: contentHeight, alignment: .topLeading)
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        window.setFrame(screenFrame(frame), display: false)
        stage.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        documents.append(window)
    }

    private func makeNote(_ note: MacNoteSnapshot, frame: CGRect) {
        let window = MacNoteWindow(contentRect: screenFrame(frame),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.setNoteStyle(noteColor: note.color)
        window.contentMinSize = CGSize(width: Layout.minNoteWidth * contentScale, height: Layout.minNoteHeight * contentScale)
        window.title = note.legacyWindowKey
        window.titleVisibility = .hidden
        let presentation = store.presentation(for: note.id)!
        window.setNoteHostingContentView(NSHostingView(rootView: MarketingGatherCaptureNote(store: store,
            presentation: presentation, noteID: note.id, scale: contentScale)
            .environment(\.locale, Locale(identifier: localeIdentifier))))
        window.addTitlebarAccessoryViewController(MacNoteTitlebarAccessoryController(
            colorPicker: NoteColorPickerTitlebarControl(store: store, presentation: presentation, noteID: note.id),
            syncIndicatorState: .hidden, store: store, presentation: presentation, noteID: note.id))
        window.applyNoteBackgroundColor(note.color.nsColor, alpha: 0.72)
        window.setFrame(screenFrame(frame), display: false)
        stage.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        windows.append(window)
        noteIDs.append(note.id)
    }

    private func capture() async throws {
        try await Swift.Task.sleep(for: .milliseconds(700))
        stage.contentView?.layoutSubtreeIfNeeded()
        effects.contentView?.layoutSubtreeIfNeeded()
        let before = windows.prefix(3).map(relativeFrame)
        let after = windows.suffix(3).map(relativeFrame)
        // A measured gap prevents native frame/layout changes from silently
        // turning the scattered scene into another overlapping cluster.
        let beforeGaps = [(0, 1), (0, 2), (1, 2)].map { a, b in
            let horizontal = max(0, max(before[a].minX - before[b].maxX, before[b].minX - before[a].maxX))
            let vertical = max(0, max(before[a].minY - before[b].maxY, before[b].minY - before[a].maxY))
            return hypot(horizontal, vertical)
        }
        let minimumBeforeGap = beforeGaps.min() ?? 0
        let sizesMatch = zip(before, after).allSatisfy { $0.size == $1.size }
        let plansMatch = (0..<3).allSatisfy { index in
            guard let a = store.note(noteIDs[index]), let b = store.note(noteIDs[index + 3]) else { return false }
            return a.title == b.title && a.color == b.color && a.tasks.map(\.text) == b.tasks.map(\.text)
        }
        func coveredFraction(_ frames: [CGRect], document: CGRect) -> CGFloat {
            let intersections = frames.map { $0.intersection(document) }
            func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
            let sum = intersections.reduce(CGFloat.zero) { $0 + area($1) }
            let pairs = area(intersections[0].intersection(intersections[1]))
                + area(intersections[0].intersection(intersections[2]))
                + area(intersections[1].intersection(intersections[2]))
            let triple = area(intersections[0].intersection(intersections[1]).intersection(intersections[2]))
            return (sum - pairs + triple) / (document.width * document.height)
        }
        let beforeCoverage = coveredFraction(before, document: relativeFrame(documents[0]))
        let afterCoverage = coveredFraction(after, document: relativeFrame(documents[1]))
        func keepsOrder(_ frames: [CGRect]) -> Bool {
            frames[0].minX < frames[2].minX && frames[2].minX < frames[1].minX
                && frames[1].minY > frames[0].minY && frames[0].minY > frames[2].minY
        }
        let afterInside = after.allSatisfy { insetFrame.insetBy(dx: -1, dy: -1).contains($0) }
        let yellowRightEdge = after[1].maxX > after[2].maxX
        let nativeOrdering = windows.allSatisfy { window in
            guard let n = NSApp.orderedWindows.firstIndex(of: window),
                  let d = NSApp.orderedWindows.firstIndex(of: documents[windows.firstIndex(of: window)! / 3]) else { return false }
            return n < d
        }
        guard minimumBeforeGap >= 20, sizesMatch, plansMatch, beforeCoverage > afterCoverage + 0.2, keepsOrder(before), keepsOrder(after), afterInside, yellowRightEdge, nativeOrdering,
              ghostFrames.count == 3, windows.allSatisfy({ !$0.title.hasPrefix("_") }) else {
            throw NSError(domain: "MarketingGatherCapture", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The native gathering composition did not preserve its required geometry."])
        }
        let file = "Tildone-macOS-screenshot-05-\(localeIdentifier).png"
        writeStatus("CAPTURING")
        try await recorder.captureImage(windowID: CGWindowID(stage.windowNumber),
            destination: outputDirectory.appendingPathComponent(file), width: 2880, height: 1800)
        func framesJSON(_ frames: [CGRect]) -> [[String: CGFloat]] {
            frames.map { ["x": $0.minX, "y": $0.minY, "width": $0.width, "height": $0.height] }
        }
        let payload: [String: Any] = [
            "status": "complete", "asset": "screenshot-5", "compositionRevision": 2,
            "locale": localeIdentifier, "preferredLocalizations": Bundle.main.preferredLocalizations,
            "mockDataOnly": true, "cloudKitStarted": false, "width": 2880, "height": 1800, "hasAlpha": false,
            "nativeNoteCount": 6, "uniquePlans": 3, "nativeDocumentCount": 2, "nativeBackgroundDocument": "textedit",
            "expandedNoteCount": 6, "minimizedNoteCount": 0, "taskCountPerNote": 2,
            "pairedNoteSizesMatch": sizesMatch, "pairedPlanContentsMatch": plansMatch,
            "beforeNotesSeparated": minimumBeforeGap >= 20, "minimumBeforeNoteGap": minimumBeforeGap,
            "beforeDocumentCoverage": beforeCoverage, "afterDocumentCoverage": afterCoverage,
            "relativeOrderPreserved": keepsOrder(before) && keepsOrder(after),
            "yellowRightEdgeVisible": yellowRightEdge, "outcomeNotesInsideInset": afterInside,
            "notesAboveDocuments": nativeOrdering, "ghostPositionMethod": "document-relative-transform",
            "ghostOutlineOpacity": ghostOpacity, "trailOpacity": trailOpacity,
            "scrollIndicator": "ScrollChevronIndicator", "scrollChevronCount": ScrollChevronLayout.count,
            "scrollPointsDown": true, "scrollAnimationFrozenForScreenshot": freezeChevron,
            "labelInsideInset": true, "labelStyle": "white-on-charcoal",
            "gatherLabel": String(localized: "Gather with a scroll."),
            "beforeNoteFrames": framesJSON(before), "afterNoteFrames": framesJSON(after),
            "ghostNoteFrames": framesJSON(ghostFrames), "documentFrames": framesJSON(documents.map(relativeFrame)),
            "noteContentScale": contentScale, "outcomeNoteAlphas": windows.suffix(3).map(\.alphaValue),
            "proDisclosureVisible": true, "proPurchaseDisclosure": String(localized: "Tildone Pro · One-time purchase"),
            "proPurchaseModel": "one-time-non-consumable", "file": file
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("screenshot-result.json"))
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
    }

    private func screenFrame(_ frame: CGRect) -> CGRect { frame.offsetBy(dx: stage.frame.minX, dy: stage.frame.minY) }
    private func relativeFrame(_ window: NSWindow) -> CGRect { window.frame.offsetBy(dx: -stage.frame.minX, dy: -stage.frame.minY) }
    private func writeStatus(_ status: String) {
        try? status.write(to: outputDirectory.appendingPathComponent("capture-status.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
