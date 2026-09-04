//
//  MacNoteTitlebarAccessoryController.swift
//  Tildone
//

import AppKit
import SwiftUI

/// Hosts Tildone's custom controls through AppKit's supported titlebar API.
/// Direct children of `NSThemeFrame` are private AppKit implementation details.
final class MacNoteTitlebarAccessoryController: NSTitlebarAccessoryViewController {
    private let colorPicker: NSView
    private let initialSyncIndicatorState: MacNoteSyncIndicatorState
    private var syncIndicator: MacNoteSyncTitlebarControl?
    private var restoreControl: MinimizedNoteRestoreTitlebarControl?

    init(colorPicker: NSView, syncIndicatorState: MacNoteSyncIndicatorState) {
        self.colorPicker = colorPicker
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
        colorPicker.frame = MacNoteTitlebarLayout.colorPickerFrame(in: view.bounds)
        syncIndicator?.frame = MacNoteTitlebarLayout.syncIndicatorFrame(
            alignedWith: colorPicker.frame
        )
        restoreControl?.frame = MacNoteTitlebarLayout.minimizedRestoreFrame(
            in: view.bounds,
            alignedWith: colorPicker.frame
        )
    }
}

extension NSWindow {
    var noteTitlebarAccessoryController: MacNoteTitlebarAccessoryController? {
        titlebarAccessoryViewControllers
            .compactMap { $0 as? MacNoteTitlebarAccessoryController }
            .first
    }
}
