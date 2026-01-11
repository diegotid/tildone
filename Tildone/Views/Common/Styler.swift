//
//  Styler.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI

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
        self.makeKeyAndOrderFront(nil)
        self.titlebarAppearsTransparent = true
        self.isReleasedWhenClosed = false
        self.makeKeyAndOrderFront(nil)
        self.standardWindowButton(.closeButton)?.style()
        self.standardWindowButton(.miniaturizeButton)?.style()
        self.standardWindowButton(.zoomButton)?.style()
        self.standardWindowButton(.zoomButton)?.isEnabled = false
        self.backgroundColor = noteColor.nsColor.withAlphaComponent(NoteWindowBackground.currentAlpha())
        self.isOpaque = false
    }

    func applyNoteBackground(isSystem: Bool, alpha: CGFloat = NoteWindowBackground.currentAlpha()) {
        let baseColor = isSystem ? NSColor.systemNoteBackground : NoteColor.current().nsColor
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

enum NoteColor: Int, CaseIterable, Identifiable {
    case yellow = 0
    case green
    case blue
    case pink
    case purple
    case orange

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        case .purple: "Purple"
        case .orange: "Orange"
        }
    }
}

extension NSButton {
    func style() {
        let frame = NSRect(x: 1, y: 2, width: 12, height: 12)
        let overlay = NSView(frame: frame)
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = frame.width / 2
        overlay.layer?.backgroundColor = NSColor.checkboxBorder.withAlphaComponent(0.2).cgColor
        self.addSubview(overlay)
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
