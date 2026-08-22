//
//  Styler.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI
import TildoneDomain

enum NoteWindowBackground {
    static let defaultAlpha: CGFloat = 0.6
    static let opacityStorageKey = "noteBackgroundOpacity"
    static let blurViewIdentifier = NSUserInterfaceItemIdentifier("NoteWindowBlurView")
    static let tintViewIdentifier = NSUserInterfaceItemIdentifier("NoteWindowTintView")

    static func currentAlpha(from defaults: UserDefaults = .standard) -> CGFloat {
        guard defaults.object(forKey: opacityStorageKey) != nil else {
            return defaultAlpha
        }
        let stored = defaults.double(forKey: opacityStorageKey)
        let clamped = min(max(stored, 0), 1)
        return CGFloat(clamped)
    }

    static func tintAlpha(configuredAlpha: CGFloat, windowAlpha: CGFloat) -> CGFloat {
        let background = min(max(configuredAlpha, 0), 1)
        let window = min(max(windowAlpha, 0), 1)
        guard window > 0 else { return 1 }
        return min(background / window, 1)
    }
}

enum NoteWindowOpacity {
    static let defaultAlpha: CGFloat = 1
    static let minimumAlpha: CGFloat = 0.1
    static let wheelStep: CGFloat = 0.05
    private static let storageKeyPrefix = "noteWindowOpacity."

    static func currentAlpha(for noteID: NoteID, defaults: UserDefaults = .standard) -> CGFloat {
        let key = storageKey(for: noteID)
        guard defaults.object(forKey: key) != nil else { return defaultAlpha }
        return clamped(CGFloat(defaults.double(forKey: key)))
    }

    static func setAlpha(_ alpha: CGFloat, for noteID: NoteID, defaults: UserDefaults = .standard) {
        defaults.set(Double(clamped(alpha)), forKey: storageKey(for: noteID))
    }

    static func adjustedAlpha(_ alpha: CGFloat, by delta: CGFloat) -> CGFloat {
        clamped(alpha + delta)
    }

    static func adjustedAlphas(_ alphas: [CGFloat], by delta: CGFloat) -> [CGFloat] {
        guard !alphas.isEmpty, delta != 0 else { return alphas }
        let clampedAlphas = alphas.map(clamped)
        if delta > 0, let lowest = clampedAlphas.min() {
            let sweep = clamped(lowest + delta)
            return clampedAlphas.map { max($0, sweep) }
        }
        guard let highest = clampedAlphas.max() else { return clampedAlphas }
        let sweep = clamped(highest + delta)
        return clampedAlphas.map { min($0, sweep) }
    }

    static func wheelDelta(for event: NSEvent) -> CGFloat? {
        wheelDelta(
            verticalDelta: CGFloat(event.scrollingDeltaY),
            horizontalDelta: CGFloat(event.scrollingDeltaX),
            usesShiftAxis: event.modifierFlags.contains(.shift),
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice,
            isPrecise: event.hasPreciseScrollingDeltas
        )
    }

    static func wheelDelta(
        verticalDelta: CGFloat,
        horizontalDelta: CGFloat = 0,
        usesShiftAxis: Bool = false,
        isDirectionInvertedFromDevice: Bool,
        isPrecise: Bool
    ) -> CGFloat? {
        let scrollingDelta = usesShiftAxis && abs(horizontalDelta) > abs(verticalDelta)
            ? horizontalDelta
            : verticalDelta
        let rawDelta = isDirectionInvertedFromDevice ? -scrollingDelta : scrollingDelta
        guard rawDelta != 0 else { return nil }
        if isPrecise {
            let scaled = min(max(abs(rawDelta) * 0.01, 0.002), wheelStep)
            return rawDelta > 0 ? scaled : -scaled
        }
        return rawDelta > 0 ? wheelStep : -wheelStep
    }

    private static func storageKey(for noteID: NoteID) -> String {
        storageKeyPrefix + noteID.stringValue
    }

    private static func clamped(_ alpha: CGFloat) -> CGFloat {
        min(max(alpha, minimumAlpha), 1)
    }
}

enum NoteWindowClickThrough {
    static let storageKey = "noteWindowsClickThrough"
    static let visualTransitionDuration: TimeInterval = 0.18

    static var isCommandPressed: Bool {
        let combined = CGEventSource.flagsState(.combinedSessionState)
        let hardware = CGEventSource.flagsState(.hidSystemState)
        return combined.contains(.maskCommand) || hardware.contains(.maskCommand)
    }

    static func shouldIgnoreMouseEvents(isEnabled: Bool, isCommandPressed: Bool) -> Bool {
        isEnabled && !isCommandPressed
    }

    static func hoverAlpha(for windowAlpha: CGFloat, isHovered: Bool) -> CGFloat {
        isHovered ? windowAlpha * 0.5 : windowAlpha
    }
}

enum Layout {
    static let checkboxSize: CGFloat = 14
    static let checkboxCheckSize: CGFloat = 8
    static let minNoteWidth: CGFloat = 180
    static let minNoteHeight: CGFloat = 240
    static let minimizedNoteWidth: CGFloat = 96
    static let minimizedNoteHeight: CGFloat = 66
    static let defaultNoteWidth: CGFloat = 250
    static let defaultNoteHeight: CGFloat = 300
    static let defaultNoteXPosition: CGFloat = 50
    static let defaultNoteYPosition: CGFloat = 90
}

extension NSColor {
    static let noteBackground = #colorLiteral(red: 1, green: 0.9411764706, blue: 0.6274509804, alpha: 1)
    static let systemNoteBackground = #colorLiteral(red: 0.7331673503, green: 0.9972032905, blue: 0.7244514823, alpha: 1)
    static let noteBlueBackground = #colorLiteral(red: 0.6823529412, green: 0.8235294118, blue: 0.9490196078, alpha: 1)
    static let notePinkBackground = #colorLiteral(red: 0.9803921569, green: 0.7803921569, blue: 0.862745098, alpha: 1)
    static let notePurpleBackground = #colorLiteral(red: 0.8431372549, green: 0.7607843137, blue: 0.9607843137, alpha: 1)
    static let noteOrangeBackground = #colorLiteral(red: 0.9882352941, green: 0.8392156863, blue: 0.7019607843, alpha: 1)
    static let checkboxBorder = #colorLiteral(red: 0.5338419676, green: 0.5067609549, blue: 0.3392150104, alpha: 1)
    static let checkboxOffFill = #colorLiteral(red: 0.9999960065, green: 1, blue: 1, alpha: 0.5)
    static let primaryFontColor = #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)
    static let primaryFontWhite = #colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)
}

extension NSWindow {
    func setNoteStyle(noteColor: NoteColor) {
        self.level = .floating
        self.titlebarAppearsTransparent = true
        self.isReleasedWhenClosed = false
        self.standardWindowButton(.closeButton)?.style()
        self.standardWindowButton(.miniaturizeButton)?.style()
        self.standardWindowButton(.zoomButton)?.style()
        self.standardWindowButton(.zoomButton)?.isEnabled = false
        self.backgroundColor = noteColor.nsColor.withAlphaComponent(NoteWindowBackground.currentAlpha())
        self.isOpaque = false
    }

    func applyNoteBackground(isSystem: Bool, alpha: CGFloat = NoteWindowBackground.currentAlpha()) {
        let baseColor = isSystem ? NSColor.systemNoteBackground : NoteColor.yellow.nsColor
        applyNoteBackgroundColor(baseColor, alpha: alpha)
    }

    func applyNoteBackgroundColor(_ color: NSColor, alpha: CGFloat = NoteWindowBackground.currentAlpha()) {
        self.backgroundColor = color.withAlphaComponent(alpha)
        guard let effectView = noteBackgroundEffectView(),
              let tintView = noteBackgroundTintView(above: effectView) else {
            DispatchQueue.main.async { [weak self] in
                self?.applyNoteBackgroundColor(color, alpha: alpha)
            }
            return
        }
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = color.withAlphaComponent(alpha).cgColor
    }

    private func noteBackgroundEffectView() -> NSVisualEffectView? {
        guard let contentView = contentView,
              let themeFrame = contentView.superview else {
            return nil
        }
        if let existingView = themeFrame.subviews.first(where: {
            $0.identifier == NoteWindowBackground.blurViewIdentifier
        }) as? NSVisualEffectView {
            return existingView
        }
        let effectView = NSVisualEffectView(frame: themeFrame.bounds)
        effectView.identifier = NoteWindowBackground.blurViewIdentifier
        effectView.autoresizingMask = [.width, .height]
        effectView.blendingMode = .behindWindow
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        themeFrame.addSubview(effectView, positioned: .below, relativeTo: nil)
        return effectView
    }

    private func noteBackgroundTintView(above effectView: NSVisualEffectView) -> NSView? {
        guard let contentView = contentView,
              let themeFrame = contentView.superview else {
            return nil
        }
        if let existingView = themeFrame.subviews.first(where: { $0.identifier == NoteWindowBackground.tintViewIdentifier }) {
            return existingView
        }
        let tintView = NSView(frame: themeFrame.bounds)
        tintView.identifier = NoteWindowBackground.tintViewIdentifier
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        themeFrame.addSubview(tintView, positioned: .below, relativeTo: contentView)
        return tintView
    }
}

extension NSButton {
    func style() {
        let frame = NSRect(x: 1, y: 2, width: 12, height: 12)
        let overlay = MouseIgnoringView(frame: frame)
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = frame.width / 2
        overlay.layer?.backgroundColor = NSColor.checkboxBorder.withAlphaComponent(0.2).cgColor
        self.addSubview(overlay)
    }
}

final class MouseIgnoringView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}
