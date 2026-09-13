//
//  MacNoteTitlebarAccessoryController.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

/// Hosts Tildone's custom controls through AppKit's supported titlebar API.
/// Direct children of `NSThemeFrame` are private AppKit implementation details.
final class MacNoteTitlebarAccessoryController: NSTitlebarAccessoryViewController {
    private let colorPicker: NSView
    private let formatControl: NSHostingView<MacTaskTextFormatMenu>
    private let kindControl: NSHostingView<MacNoteKindMenu>
    private let initialSyncIndicatorState: MacNoteSyncIndicatorState
    private var syncIndicator: MacNoteSyncTitlebarControl?
    private var restoreControl: MinimizedNoteRestoreTitlebarControl?

    init(
        colorPicker: NSView,
        syncIndicatorState: MacNoteSyncIndicatorState,
        store: MacSharedStore,
        presentation: MacNotePresentation,
        noteID: NoteID
    ) {
        self.colorPicker = colorPicker
        let formatControl = NSHostingView(rootView: MacTaskTextFormatMenu(
            store: store, presentation: presentation, noteID: noteID
        ))
        let kindControl = NSHostingView(rootView: MacNoteKindMenu(
            store: store, presentation: presentation, noteID: noteID
        ))
        // These controls are positioned explicitly beside the AppKit color
        // picker. Prevent localized SwiftUI menu content from changing their
        // hosting-view frames after the titlebar has laid them out.
        formatControl.sizingOptions = []
        kindControl.sizingOptions = []
        self.formatControl = formatControl
        self.kindControl = kindControl
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
        container.addSubview(formatControl)
        container.addSubview(kindControl)
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
        formatControl.isHidden = hidden
        kindControl.isHidden = hidden
    }

    func setFormatControlForeground(_ foreground: Color) {
        loadViewIfNeeded()
        formatControl.rootView = MacTaskTextFormatMenu(
            store: formatControl.rootView.store,
            presentation: formatControl.rootView.presentation,
            noteID: formatControl.rootView.noteID,
            foreground: foreground
        )
        formatControl.needsLayout = true
        formatControl.needsDisplay = true
        kindControl.rootView = MacNoteKindMenu(
            store: kindControl.rootView.store,
            presentation: kindControl.rootView.presentation,
            noteID: kindControl.rootView.noteID,
            foreground: foreground
        )
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
        let accessoryWidth = MacNoteTitlebarLayout.accessoryWidth
        if abs(view.frame.width - accessoryWidth) > 0.5 {
            view.setFrameSize(NSSize(width: accessoryWidth, height: view.frame.height))
        }
        colorPicker.frame = MacNoteTitlebarLayout.colorPickerFrame(in: view.bounds)
        formatControl.frame = MacNoteTitlebarLayout.formatControlFrame(
            alignedWith: colorPicker.frame
        )
        kindControl.frame = MacNoteTitlebarLayout.kindControlFrame(alignedWith: colorPicker.frame)
        syncIndicator?.frame = MacNoteTitlebarLayout.syncIndicatorFrame(
            alignedWith: colorPicker.frame
        )
        restoreControl?.frame = MacNoteTitlebarLayout.minimizedRestoreFrame(
            in: view.bounds,
            alignedWith: colorPicker.frame
        )
    }
}

private struct MacNoteKindMenu: View {
    let store: MacSharedStore
    @ObservedObject var presentation: MacNotePresentation
    let noteID: NoteID
    var foreground: Color = .primary

    var body: some View {
        Menu {
            Button { setKind(.checklist) } label: {
                Label("Task list", systemImage: "checklist")
            }
            Button { setKind(.singleTask) } label: {
                Label("Single memo", systemImage: "text.aligncenter")
            }
        } label: {
            Image(systemName: presentation.snapshot.kind == .checklist ? "checklist" : "text.aligncenter")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foreground)
                .frame(width: MacNoteTitlebarLayout.kindControlWidth, height: MacNoteTitlebarLayout.controlHeight)
                .contentShape(Rectangle())
                .offset(y: 3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(foreground)
        .help("Note type")
        .accessibilityLabel("Note type")
    }

    private func setKind(_ kind: NoteKind) {
        Swift.Task { try? await store.setKind(kind, for: noteID) }
    }
}

extension NSWindow {
    var noteTitlebarAccessoryController: MacNoteTitlebarAccessoryController? {
        if let noteWindow = self as? MacNoteWindow,
           noteWindow.hasDetachedTitlebarAccessories {
            return noteWindow.detachedNoteTitlebarAccessoryController
        }
        return titlebarAccessoryViewControllers
            .compactMap { $0 as? MacNoteTitlebarAccessoryController }
            .first
    }
}
