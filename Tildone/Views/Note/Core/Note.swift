//
//  Note.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

/// A macOS note window backed solely by shared-domain snapshots. AppKit state
/// (focus, fade, minimization and window styling) deliberately remains here.
struct Note: View {
    @ObservedObject var store: MacSharedStore
    let noteID: NoteID

    @Environment(\.colorScheme) var colorScheme
    @AppStorage(TaskLineTruncation.storageKey) var taskLineTruncation: TaskLineTruncation = .single
    @AppStorage(FontSize.storageKey) var fontSize = Double(FontSize.small.rawValue)
    @AppStorage(NoteWindowBackground.opacityStorageKey) var noteBackgroundOpacity = Double(NoteWindowBackground.defaultAlpha)
    @AppStorage(AppAppearance.moveCheckedTasksToEndStorageKey) var moveCheckedTasksToEnd = false
    @AppStorage(NoteWindowClickThrough.storageKey) var clickThroughNotes = false

    var note: MacNoteSnapshot? { store.note(noteID) }
    var tasks: [TildoneDomain.Task] { note?.tasks ?? [] }
    var pendingTasks: [TildoneDomain.Task] { tasks.filter { !$0.isCompleted } }
    var isDark: Bool { colorScheme == .dark && noteBackgroundOpacity < 0.5 }
    var noteColor: NoteColor { note?.color ?? .yellow }
    var color: NSColor { noteColor.nsColor }
    var noteForeground: Color {
        isDark ? Color(.primaryFontWhite) : .black
    }
    var isInsertedNewTaskFocused: Bool {
        guard let focusedTaskID = activeFocusedTaskID else { return false }
        return tasks.contains { $0.id == focusedTaskID && $0.text.isEmpty }
    }
    var activeFocusedTaskID: TaskID? {
        nativeFocusedTaskID ?? focusedTaskID
    }
    var isMinimized: Bool { minimizationState.isMinimized }
    var minimizedForeground: Color {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let colorLuminance = 0.2126 * rgb.redComponent
            + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
        let backdropLuminance: CGFloat = colorScheme == .dark ? 0 : 1
        let opacity = CGFloat(noteBackgroundOpacity * windowAlpha)
        let backgroundLuminance = colorLuminance * opacity + backdropLuminance * (1 - opacity)
        return backgroundLuminance > 0.55 ? .black.opacity(0.75) : .white.opacity(0.75)
    }
    var isDone: Bool { completionFade.showsCompletionOverlay }
    var isContentBlurred: Bool {
        Self.shouldBlurContent(
            isFocusBlurred: isTextBlurred,
            isClickThroughEnabled: clickThroughNotes,
            isHovering: isPointerHovering
        )
    }

    static func shouldBlurContent(
        isFocusBlurred: Bool,
        isClickThroughEnabled: Bool,
        isHovering: Bool
    ) -> Bool {
        isFocusBlurred && (isClickThroughEnabled || !isHovering)
    }

    enum Field: Hashable { case topic, newTask }

    @State var noteWindow: NSWindow?
    @State var newTaskText = ""
    @State var isTextBlurred = false
    @State var isPointerHovering = false
    @State var isTopScrolledOut = false
    @State var isTopicHidden = false
    @State var didSetInitialFocus = false
    @State var windowAlpha = 1.0
    @State var minimizationState = NoteWindowMinimizationState()
    @State var completionFade = CompletionFadeLifecycle()
    @State var fadeAwayProgress: TimeInterval = 0
    @State var mutationErrorMessage: String?
    @State var taskDropFeedbackResetToken = UUID()
    @State var skipsNextTaskCountBottomScroll = false
    @State var completedTaskMovementAnimationID: TaskID?
    @State var keyboardFocusedTaskID: TaskID?
    @State var nativeFocusedTaskID: TaskID?
    @FocusState var focusedField: Field?
    @FocusState var focusedTaskID: TaskID?

    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(store: MacSharedStore, noteID: NoteID) {
        self.store = store
        self.noteID = noteID
    }

    var body: some View {
        Group {
            if let note {
                if isMinimized {
                    taskListProgress(note)
                } else {
                    taskList(note)
                }
            }
        }
        .onChange(of: note?.color) { _, _ in applyCurrentNoteBackground() }
        .onChange(of: isMinimized) { _, minimized in setTrafficLightsHidden(minimized) }
        .onChange(of: noteBackgroundOpacity) { _, _ in applyCurrentNoteBackground() }
        .onReceive(NotificationCenter.default.publisher(for: .noteWindowOpacityChanged)) { notification in
            guard let changedWindow = notification.object as? NSWindow,
                  changedWindow === noteWindow else { return }
            applyCurrentNoteBackground()
        }
        .onAppear {
            synchronizeCompletionFade(completedAt: note?.completedAt)
        }
        .onChange(of: note?.completedAt) { _, completedAt in
            synchronizeCompletionFade(completedAt: completedAt)
        }
        .background {
            if completionFade.isFading {
                Color.clear
                    .frame(width: 0, height: 0)
                    .onReceive(timer, perform: advanceCompletionFade)
            }
        }
        .alert("Couldn’t save this change", isPresented: Binding(
            get: { mutationErrorMessage != nil },
            set: { if !$0 { mutationErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { mutationErrorMessage = nil }
        } message: {
            Text(mutationErrorMessage ?? String(localized: "Your notes remain on this Mac."))
        }
    }
}
