#if MARKETING_CAPTURE
import AppKit
import SwiftUI
import TildoneDomain
import TildonePersistence
import ImageIO
import UniformTypeIdentifiers

/// Sequential native captures preserve the app's global appearance semantics.
@available(macOS 15, *)
@MainActor
final class MarketingAppearanceCaptureDirector: NSObject, NSApplicationDelegate, ObservableObject {
    let canvasSize = CGSize(width: 1440, height: 900)
    let settingsFrame = CGRect(x: 85, y: 50, width: 410, height: 310)
    let weekendFrame = CGRect(x: 570, y: 310, width: 405, height: 310)
    let homeFrame = CGRect(x: 385, y: 220, width: 325, height: 240)
    let laterFrame = CGRect(x: 1030, y: 195, width: 325, height: 240)
    var dimmingCaptionCenter: CGPoint { CGPoint(x: laterFrame.midX, y: laterFrame.minY - 48) }
    @Published private(set) var images: [Int: NSImage] = [:]
    private(set) var cropFrames: [Int: CGRect] = [:]
    private var stage: NSWindow!
    private var settingsWindow: NSWindow?
    private var currentWindow: MacNoteWindow?
    private var store: MacSharedStore!
    private var noteIDs: [NoteID] = []
    private var sampleProof: [[String: Any]] = []
    private var noteFrames: [Int: CGRect] = [:]
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

    private func preferences(fontSize: Double, backgroundOpacity: Double) {
        var values = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        values[FontSize.storageKey] = fontSize
        values[NoteWindowBackground.opacityStorageKey] = backgroundOpacity
        values[NoteColor.storageKey] = NoteColor.green.legacyRawValue
        values[TaskLineTruncation.storageKey] = TaskLineTruncation.multiple.rawValue
        values[NoteWindowClickThrough.storageKey] = false
        values["taskSpellCheckingEnabled"] = false
        values["completedWelcomeOnboarding"] = true
        values["seenWhatsNewContent"] = WhatsNewRelease.contentID
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
    }

    private func prepare() async throws {
        // A failed screen-region attempt intentionally leaves its mock scene
        // visible. Close only older instances of this same private capture app
        // before a retry, so their floating windows cannot contaminate the rect.
        for application in NSRunningApplication.runningApplications(withBundleIdentifier: "studio.cuatro.tildone.marketing-preview")
            where application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            application.terminate()
        }
        preferences(fontSize: 20, backgroundOpacity: 0.65)
        let repository = try TildoneRepository(descriptor: .inMemory())
        store = MacSharedStore(repository: repository)
        store.setUndoEnabled(false)
        let fixtures: [(String, NoteColor, [String])] = [
            (String(localized: "Weekend plans"), .green, [String(localized: "Find a quiet place to read"),
                String(localized: "Take the scenic route"), String(localized: "Leave the afternoon free")]),
            (String(localized: "At home"), .purple, [String(localized: "Water the plants"), String(localized: "Pick up the parcel")]),
            (String(localized: "Later"), .orange, [String(localized: "Compare paint samples"), String(localized: "Choose a desk lamp")])
        ]
        for (title, color, tasks) in fixtures {
            let note = try await store.createNote(color: color)
            try await store.renameNote(note.id, to: title)
            for text in tasks { _ = try await store.addTask(to: note.id, text: text) }
            noteIDs.append(note.id)
        }
        let screens = ([NSScreen.main].compactMap { $0 } + NSScreen.screens)
        guard let screen = screens.first(where: { $0.visibleFrame.width >= 1440 && $0.visibleFrame.height >= 900 }) else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "The full marketing canvas must fit inside a visible 1440 × 900 screen area.")])
        }
        guard let wallpaper = NSImage(contentsOfFile: Bundle.main.path(forResource: "GoldenGate", ofType: "png") ?? "") else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 1)
        }
        stage = NSWindow(contentRect: CGRect(x: (screen.visibleFrame.midX - 720).rounded(),
            y: (screen.visibleFrame.midY - 450).rounded(), width: 1440, height: 900),
            styleMask: .borderless, backing: .buffered, defer: false)
        stage.isReleasedWhenClosed = false
        stage.appearance = NSAppearance(named: .aqua)
        stage.contentView = NSHostingView(rootView: MarketingAppearanceCaptureBackdrop(director: self, wallpaper: wallpaper)
            .environment(\.locale, Locale(identifier: localeIdentifier)))
        stage.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try FileManager.default.createDirectory(at: outputDirectory.appendingPathComponent("native-frames"),
                                               withIntermediateDirectories: true)
        try await Swift.Task.sleep(for: .seconds(1))
    }

    private func makeNote(index: Int, frame: CGRect) -> (MacNoteWindow, NoteColorPickerTitlebarControl) {
        let note = store.note(noteIDs[index])!
        let window = MacNoteWindow(contentRect: screenFrame(frame),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.setNoteStyle(noteColor: note.color)
        window.contentMinSize = CGSize(width: Layout.minNoteWidth, height: Layout.minNoteHeight)
        window.title = note.legacyWindowKey
        window.titleVisibility = .hidden
        let presentation = store.presentation(for: note.id)!
        window.setNoteHostingContentView(NSHostingView(rootView: Note(store: store, presentation: presentation, noteID: note.id)
            .environment(\.locale, Locale(identifier: localeIdentifier))))
        let picker = NoteColorPickerTitlebarControl(store: store, presentation: presentation, noteID: note.id)
        window.addTitlebarAccessoryViewController(MacNoteTitlebarAccessoryController(colorPicker: picker,
            syncIndicatorState: .hidden, store: store, presentation: presentation, noteID: note.id))
        window.applyNoteBackgroundColor(note.color.nsColor, alpha: NoteWindowBackground.currentAlpha())
        window.setFrame(screenFrame(frame), display: false)
        stage.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        currentWindow = window
        return (window, picker)
    }

    private func captureSample(index: Int, frame: CGRect, fontSize: Double,
                               backgroundOpacity: Double, windowAlpha: CGFloat, palette: Bool, retainForFinal: Bool = false) async throws {
        preferences(fontSize: fontSize, backgroundOpacity: backgroundOpacity)
        let (window, picker) = makeNote(index: index, frame: frame)
        defer {
            if picker.marketingPopoverFrame != nil { _ = picker.accessibilityPerformPress() }
            if !retainForFinal {
                stage.removeChildWindow(window)
                window.orderOut(nil)
                window.contentView = nil
                window.close()
                currentWindow = nil
            }
        }
        try await Swift.Task.sleep(for: .milliseconds(1100))
        window.makeFirstResponder(nil)
        window.setFrame(screenFrame(frame), display: true)
        window.alphaValue = NoteWindowOpacity.adjustedAlpha(1, by: windowAlpha - 1)
        NotificationCenter.default.post(name: .noteWindowOpacityChanged, object: window)
        try await Swift.Task.sleep(for: .milliseconds(350))
        var popupFrame: CGRect?
        if palette {
            guard picker.accessibilityPerformPress() else { throw NSError(domain: "MarketingAppearanceCapture", code: 2) }
            try await Swift.Task.sleep(for: .milliseconds(400))
            // Keep a native popover's actual placement below the marketing copy.
            if let popup = picker.marketingPopoverFrame {
                let excess = relativeFrame(popup).maxY - 670
                if excess > 0 {
                    _ = picker.accessibilityPerformPress()
                    window.setFrameOrigin(CGPoint(x: window.frame.minX, y: window.frame.minY - excess))
                    _ = picker.accessibilityPerformPress()
                    try await Swift.Task.sleep(for: .milliseconds(300))
                }
            }
            popupFrame = picker.marketingPopoverFrame.map(relativeFrame)
            guard popupFrame != nil else { throw NSError(domain: "MarketingAppearanceCapture", code: 3) }
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let snapshot = store.note(noteIDs[index])!
        let fields = descendants(window.contentView!).compactMap { $0 as? NSTextField }
        let taskFields = fields.filter { field in snapshot.tasks.contains(where: { $0.text == field.stringValue }) }
        let taskSizes = taskFields.compactMap { field -> CGFloat? in
            // Task editors store the displayed typeface in attributed text;
            // NSTextField.font can remain its unrelated default cell font.
            guard field.attributedStringValue.length > 0 else { return nil }
            return (field.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
        }
        let nativeTitle = fields.contains { $0.stringValue == snapshot.title }
        guard taskFields.count >= snapshot.tasks.count, nativeTitle,
              !taskSizes.isEmpty, taskSizes.allSatisfy({ abs($0 - fontSize) < 0.1 }),
              abs(window.alphaValue - windowAlpha) < 0.001,
              backgroundOpacity != 0 || window.backgroundColor?.alphaComponent == 0 else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "The native appearance example did not match its requested text size, title or opacity."])
        }
        var crop = relativeFrame(window.frame).insetBy(dx: -18, dy: -18)
        if let popupFrame { crop = crop.union(popupFrame.insetBy(dx: -12, dy: -12)) }
        crop = crop.intersection(CGRect(origin: .zero, size: canvasSize)).integral
        let source = outputDirectory.appendingPathComponent("native-frames/example-\(index).png")
        writeStatus("CAPTURING NATIVE APPEARANCE \(index + 1)/3")
        try await recorder.captureImage(windowID: CGWindowID(stage.windowNumber), destination: source, width: 2880, height: 1800)
        guard let cgSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(cgSource, 0, nil),
              let cropped = original.cropping(to: CGRect(x: crop.minX * 2,
                  y: (canvasSize.height - crop.maxY) * 2, width: crop.width * 2, height: crop.height * 2)) else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 5)
        }
        cropFrames[index] = crop
        noteFrames[index] = relativeFrame(window.frame)
        // Keep the transparent note live above the real Settings window.
        // Painting its crop behind itself would contaminate its backdrop.
        if !retainForFinal { images[index] = NSImage(cgImage: cropped, size: crop.size) }
        sampleProof.append([
            "keptLiveForFinalCapture": retainForFinal,
            "index": index, "color": snapshot.color.rawValue, "taskCount": snapshot.tasks.count,
            "fontSizeSetting": fontSize, "nativeTaskFontSizes": taskSizes, "nativeTitleVisible": nativeTitle,
            "backgroundOpacitySetting": backgroundOpacity, "nativeBackgroundAlpha": window.backgroundColor?.alphaComponent ?? -1,
            "windowAlpha": window.alphaValue, "nativeVisualEffectMaterialRetained": containsMaterial(window.contentView!),
            "nativeWindowShadow": window.hasShadow, "nativePaletteVisible": popupFrame != nil,
            "paletteColorCount": palette ? NoteColor.allCases.count : 0,
            "source": source.lastPathComponent, "cropFrame": frameJSON(crop), "windowFrame": frameJSON(relativeFrame(window.frame))
        ])
    }

    private func makeSettingsWindow() {
        preferences(fontSize: 15, backgroundOpacity: 0)
        var form = SettingsForm(store: store)
        form.marketingAppearanceOnly = true
        let window = NSWindow(contentRect: screenFrame(settingsFrame), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let host = NSHostingView(rootView: form.environment(\.locale, Locale(identifier: localeIdentifier)))
        host.sizingOptions = []
        window.contentView = host
        stage.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        settingsWindow = window
    }

    private func capture() async throws {
        try await captureSample(index: 0, frame: weekendFrame,
                                fontSize: 20, backgroundOpacity: 0.65, windowAlpha: 1, palette: true)
        try await captureSample(index: 2, frame: laterFrame,
                                fontSize: 15, backgroundOpacity: 0.65, windowAlpha: 0.45, palette: false)
        // Settings is an actual native window behind the transparent note.
        // Weekend remains its previously captured global-settings example.
        makeSettingsWindow()
        try await Swift.Task.sleep(for: .milliseconds(400))
        try await captureSample(index: 1, frame: homeFrame,
                                fontSize: 15, backgroundOpacity: 0, windowAlpha: 1,
                                palette: false, retainForFinal: true)
        guard let home = currentWindow, let settings = settingsWindow,
              let weekend = noteFrames[0], let later = noteFrames[2] else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 6)
        }
        home.order(.above, relativeTo: settings.windowNumber)
        home.makeFirstResponder(nil)
        try await Swift.Task.sleep(for: .milliseconds(600))
        stage.contentView?.layoutSubtreeIfNeeded()
        settings.contentView?.layoutSubtreeIfNeeded()
        home.contentView?.layoutSubtreeIfNeeded()
        let actualHome = relativeFrame(home.frame)
        let actualSettings = relativeFrame(settings.frame)
        let overlapsWeekendCorner = actualHome.contains(CGPoint(x: weekend.minX + 1, y: weekend.minY + 1))
        let overlapsSettingsCorner = actualHome.contains(CGPoint(x: actualSettings.maxX - 1, y: actualSettings.maxY - 1))
        let homeIndex = NSApp.orderedWindows.firstIndex(of: home)
        let settingsIndex = NSApp.orderedWindows.firstIndex(of: settings)
        let aboveSettings = homeIndex != nil && settingsIndex != nil && homeIndex! < settingsIndex!
        let horizontalGap = later.minX - weekend.maxX
        guard images.count == 2, images[1] == nil, sampleProof.count == 3,
              home.isVisible, aboveSettings, overlapsWeekendCorner, overlapsSettingsCorner,
              horizontalGap >= 40, later.maxY < canvasSize.height / 2,
              home.backgroundColor?.alphaComponent == 0, home.alphaValue == 1,
              sampleProof.allSatisfy({ $0["nativeVisualEffectMaterialRetained"] as? Bool == true }) else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "The live transparent note must overlap both background examples and stay above Settings."])
        }
        sampleProof.sort { ($0["index"] as! Int) < ($1["index"] as! Int) }
        let file = "Tildone-macOS-screenshot-06-\(localeIdentifier).png"
        let regionProof = try await captureScreenRegion(destination: outputDirectory.appendingPathComponent(file))
        let payload: [String: Any] = [
            "status": "complete", "asset": "screenshot-6", "compositionRevision": 3,
            "locale": localeIdentifier, "preferredLocalizations": Bundle.main.preferredLocalizations,
            "mockDataOnly": true, "cloudKitStarted": false, "width": 2880, "height": 1800, "hasAlpha": false,
            "nativeNoteCount": 3, "totalTaskCount": 7, "maxIndentLevel": 0, "singleMemoCount": 0,
            "compositionMethod": "screen-region-with-live-transparent-note",
            "finalCaptureMethod": regionProof["method"]!, "screenRegion": regionProof, "globalSettingsCapturedSeparately": true,
            "liveTransparentNote": true, "transparentNoteAboveSettings": aboveSettings,
            "transparentOverlapsWeekendCorner": overlapsWeekendCorner, "transparentOverlapsSettingsCorner": overlapsSettingsCorner,
            "weekendLaterHorizontalGap": horizontalGap, "dimmingGroupBelowMidline": later.maxY < canvasSize.height / 2,
            "transparentMaterialNeedsVisualReview": true,
            "nativeNoteView": "Note", "contentScale": 1, "samples": sampleProof,
            "nativePaletteVisible": true, "nativePaletteColorCount": 6,
            "settingsView": "SettingsForm", "settingsControlsReused": ["noteColorSettings", "fontSizeSettings", "taskWrappingSettings"],
            "settingsFrame": frameJSON(actualSettings), "dimmingCaptionCenter": ["x": dimmingCaptionCenter.x, "y": dimmingCaptionCenter.y], "noExampleLabels": true, "noOuterExampleBorder": true,
            "dimmingCaption": String(localized: "Dim notes with a scroll."),
            "proDisclosureScope": "dimming-only", "proPurchaseDisclosure": String(localized: "Tildone Pro · One-time purchase"),
            "proPurchaseModel": "one-time-non-consumable", "file": file
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("screenshot-result.json"))
        writeStatus("COMPLETE")
        NSApp.terminate(nil)
    }

    /// A GUI-session helper captures the display rectangle. Window snapshots
    /// flatten behind-window materials, so they cannot export this final scene.
    private func captureScreenRegion(destination: URL) async throws -> [String: Any] {
        guard let screen = stage.screen,
              screen.frame.contains(stage.frame), screen.visibleFrame.contains(stage.frame),
              let primary = NSScreen.screens.first else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "The full marketing canvas must fit inside a visible 1440 × 900 screen area.")])
        }
        let rect = CGRect(x: stage.frame.minX, y: primary.frame.maxY - stage.frame.maxY,
                          width: stage.frame.width, height: stage.frame.height)
        let token = UUID().uuidString
        let rawFile = "native-frames/screen-region-native.png"
        let acknowledgement = outputDirectory.appendingPathComponent("screen-region-complete.json")
        try? FileManager.default.removeItem(at: acknowledgement)
        let request: [String: Any] = [
            "bundleIdentifier": Bundle.main.bundleIdentifier!, "asset": "screenshot-6", "compositionRevision": 3,
            "sceneToken": token, "locale": localeIdentifier, "rawFile": rawFile,
            "canvasFullyOnScreen": true, "canvasWithinVisibleFrame": true,
            "backingScaleFactor": screen.backingScaleFactor,
            "rect": ["x": Int(rect.minX), "y": Int(rect.minY), "width": 1440, "height": 900]
        ]
        try JSONSerialization.data(withJSONObject: request, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("screen-region-request.json"), options: .atomic)
        writeStatus("READY FOR SCREEN REGION")
        // Keep the live scene visible if capture fails or the user needs to
        // grant Terminal permission / choose a rectangle manually.
        while !FileManager.default.fileExists(atPath: acknowledgement.path) {
            try await Swift.Task.sleep(for: .milliseconds(100))
        }
        let ack = try JSONSerialization.jsonObject(with: Data(contentsOf: acknowledgement)) as! [String: Any]
        guard ack["sceneToken"] as? String == token, ack["rawFile"] as? String == rawFile,
              let method = ack["method"] as? String,
              ["macos-screencapture-region", "macos-screencapture-interactive-region"].contains(method),
              let source = CGImageSourceCreateWithURL(outputDirectory.appendingPathComponent(rawFile) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              abs(Double(image.width) / Double(image.height) - 1.6) <= 0.002,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 2880, height: 1800, bitsPerComponent: 8,
                  bytesPerRow: 2880 * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 9)
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2880, height: 1800))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
        guard let rgb = context.makeImage(),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MarketingAppearanceCapture", code: 10)
        }
        CGImageDestinationAddImage(output, rgb, nil)
        guard CGImageDestinationFinalize(output) else { throw NSError(domain: "MarketingAppearanceCapture", code: 11) }
        return ["method": method, "rawFile": rawFile, "rect": request["rect"]!,
                "canvasFullyOnScreen": true, "sourceWidth": image.width, "sourceHeight": image.height,
                "backingScaleFactor": screen.backingScaleFactor, "windowCaptureUsed": false]
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func containsMaterial(_ view: NSView) -> Bool { descendants(view).contains { $0 is NSVisualEffectView } }
    private func screenFrame(_ frame: CGRect) -> CGRect { frame.offsetBy(dx: stage.frame.minX, dy: stage.frame.minY) }
    private func relativeFrame(_ frame: CGRect) -> CGRect { frame.offsetBy(dx: -stage.frame.minX, dy: -stage.frame.minY) }
    private func frameJSON(_ frame: CGRect) -> [String: CGFloat] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }
    private func writeStatus(_ status: String) {
        try? status.write(to: outputDirectory.appendingPathComponent("capture-status.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
