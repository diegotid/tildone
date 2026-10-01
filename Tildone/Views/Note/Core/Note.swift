//
//  Note.swift
//  Tildone
//

import Combine
import SwiftUI
import TildoneDomain

/// A macOS note window backed solely by shared-domain snapshots. AppKit state
/// (focus, fade, minimization and window styling) deliberately remains here.
struct Note: View {
    let store: MacSharedStore
    @ObservedObject var presentation: MacNotePresentation
    let noteID: NoteID

    @Environment(\.colorScheme) var colorScheme
    @AppStorage(TaskLineTruncation.storageKey) var taskLineTruncation: TaskLineTruncation = .single
    @AppStorage(FontSize.storageKey) var fontSize = Double(FontSize.small.rawValue)
    @AppStorage(NoteWindowBackground.opacityStorageKey) var noteBackgroundOpacity = Double(NoteWindowBackground.defaultAlpha)
    @AppStorage(CompactNoteScale.storageKey) var compactNoteScale = CompactNoteScale.defaultValue
    @AppStorage(AppAppearance.moveCheckedTasksToEndStorageKey) var moveCheckedTasksToEnd = false
    @AppStorage(NoteWindowClickThrough.storageKey) var clickThroughNotes = false

    var note: MacNoteSnapshot? { presentation.snapshot }
    var tasks: [TildoneDomain.Task] { note?.tasks ?? [] }
    var pendingTasks: [TildoneDomain.Task] { tasks.filter { !$0.isCompleted } }
    var isDark: Bool {
        NoteContentForeground.usesLightText(
            colorScheme: colorScheme,
            backgroundOpacity: noteBackgroundOpacity,
            windowOpacity: contentWindowAlpha
        )
    }
    var noteColor: NoteColor { note?.color ?? .yellow }
    var noteKind: NoteKind { note?.kind ?? .checklist }
    var color: NSColor { noteColor.nsColor }
    var noteForeground: Color {
        NoteContentForeground.color(
            colorScheme: colorScheme,
            backgroundOpacity: noteBackgroundOpacity,
            windowOpacity: contentWindowAlpha
        )
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
        // Pastel note colors still appear light at the normal note opacity,
        // even when they are composited over the dark desktop. Keep their
        // minimized content dark; reserve light content for genuinely dark
        // or heavily transparent notes.
        return backgroundLuminance > 0.45 ? .black.opacity(0.75) : .white.opacity(0.75)
    }
    var isDone: Bool { completionFade.showsCompletionOverlay }
    var isContentBlurred: Bool {
        Self.shouldBlurContent(
            isFocusBlurred: isTextBlurred,
            isClickThroughEnabled: clickThroughNotes,
            isHovering: isPointerHovering,
            isCommandInteractionActive: isClickThroughCommandInteractionActive
        )
    }

    static func shouldBlurContent(
        isFocusBlurred: Bool,
        isClickThroughEnabled: Bool,
        isHovering: Bool,
        isCommandInteractionActive: Bool
    ) -> Bool {
        isFocusBlurred && (isClickThroughEnabled || !isHovering) && !isCommandInteractionActive
    }

    enum Field: Hashable { case topic, newTask }

    @State var noteWindow: NSWindow?
    @State var newTaskText = ""
    @State var newTaskIndentLevel: Int?
    var newTaskInsertionIndex: Int {
        Self.newTaskInsertionIndex(in: tasks, moveCompletedToBottom: moveCheckedTasksToEnd)
    }
    var newTaskDraftIndentLevel: Int {
        guard newTaskInsertionIndex > 0 else { return 0 }
        return newTaskIndentLevel ?? tasks[newTaskInsertionIndex - 1].indentLevel
    }
    @State var isTextBlurred = false
    @State var isPointerHovering = false
    @State var isClickThroughCommandInteractionActive = false
    @State var isTopScrolledOut = false
    @State var isTopicHidden = false
    @State var didSetInitialFocus = false
    @State var windowAlpha = 1.0
    @State var contentWindowAlpha: CGFloat = 1
    @State var minimizationState = NoteWindowMinimizationState()
    @State var completionFade = CompletionFadeLifecycle()
    @State var fadeAwayProgress: TimeInterval = 0
    @State var completionFadeBaseWindowAlpha: CGFloat?
    @State var didRaiseWindowForCompletionFade = false
    @State var mutationErrorMessage: String?
    @State var taskDropFeedbackResetToken = UUID()
    @State var isHoveringMinimizedTaskList = false
    @State var skipsNextTaskCountBottomScroll = false
    @State var completedTaskMovementAnimationID: TaskID?
    @State var optimisticTaskCompletions: [TaskID: Bool] = [:]
    @State var hoveredTaskID: TaskID?
    @State var collapsedTaskIDs: Set<TaskID> = []
    @State var keyboardMonitor: Any?
    @State var isEmptySingleMemoHintDismissed = false
    @State var isImportingPastedList = false
    @State var proAccessToast: ProAccessRequest?
    @State var findQuery = ""

    var shouldShowEmptySingleMemoHint: Bool {
        !isEmptySingleMemoHintDismissed
            && noteKind == .checklist
            && note?.title == nil
            && tasks.isEmpty
            && newTaskText.isEmpty
    }

    var visibleTaskEntries: [(index: Int, task: TildoneDomain.Task)] {
        var collapsedDepth: Int?
        return tasks.enumerated().compactMap { index, task in
            if let depth = collapsedDepth {
                if task.indentLevel > depth {
                    return nil
                }
                collapsedDepth = nil
            }
            if collapsedTaskIDs.contains(task.id) {
                collapsedDepth = task.indentLevel
            }
            return (index, task)
        }
    }
    @State var keyboardFocusedTaskID: TaskID?
    @State var nativeFocusedTaskID: TaskID?
    @State var singleTaskDraft = RichText(text: "")
    @State var singleTaskDraftID: TaskID?
    @State var stagedSingleMemoTaskID: TaskID?
    @State var singleMemoTitleCaretOffset: Int?
    // Both capture fields are AppKit-backed; there is no SwiftUI .focused
    // binding to retain a FocusState value or carry a focus request to them.
    @State var focusedField: Field?
    @FocusState var focusedTaskID: TaskID?

    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(
        store: MacSharedStore,
        presentation: MacNotePresentation,
        noteID: NoteID,
        initialFocusBlurred: Bool = false,
        initialMinimizationState: NoteWindowMinimizationState = NoteWindowMinimizationState()
    ) {
        self.store = store
        self.presentation = presentation
        self.noteID = noteID
        _isTextBlurred = State(initialValue: initialFocusBlurred)
        _minimizationState = State(initialValue: initialMinimizationState)
    }

    var body: some View {
        Group {
            if let note {
                if isMinimized {
                    taskListProgress(note)
                } else if note.kind == .singleTask {
                    singleTaskNote(note)
                } else {
                    taskList(note)
                }
            }
        }
        .onAppear { presentation.onKindChange = { handleNoteKindChange($0) } }
        .onDisappear { presentation.onKindChange = nil }
        .overlay(alignment: .bottom) {
            if let proAccessToast, !isMinimized {
                proAccessHint(for: proAccessToast)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: proAccessToast?.id)
        .onReceive(ProEntitlement.shared.$deniedRequest.dropFirst().compactMap { $0 }) { request in
            guard request.noteID == noteID else { return }
            proAccessToast = request
        }
        .task(id: proAccessToast?.id) {
            guard let requestID = proAccessToast?.id else { return }
            try? await Swift.Task.sleep(for: .seconds(7))
            if proAccessToast?.id == requestID { proAccessToast = nil }
        }
        .onChange(of: note?.color) { _, _ in
            applyCurrentNoteBackground()
            updateRestoreControlForeground()
        }
        .onChange(of: noteWindow) { _, window in
            contentWindowAlpha = window?.alphaValue ?? 1
            updateWindowMenuTitle()
            updateFormatControlForeground()
            setTrafficLightsHidden(isMinimized)
            setColorPickerHidden(isMinimized)
        }
        .onChange(of: note?.title) { _, _ in
            updateWindowMenuTitle()
        }
        .onChange(of: isMinimized) { _, minimized in
            setTrafficLightsHidden(minimized)
            if minimized { isHoveringMinimizedTaskList = false }
        }
        .onChange(of: noteBackgroundOpacity) { _, _ in
            applyCurrentNoteBackground()
            updateRestoreControlForeground()
            updateFormatControlForeground()
        }
        .onChange(of: colorScheme) { _, _ in
            updateFormatControlForeground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteWindowOpacityChanged)) { notification in
            guard let changedWindow = notification.object as? NSWindow,
                  changedWindow === noteWindow else { return }
            contentWindowAlpha = changedWindow.alphaValue
            applyCurrentNoteBackground()
            updateRestoreControlForeground()
            updateFormatControlForeground()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findQueryChanged)) { notification in
            findQuery = notification.object as? String ?? ""
        }
        .onAppear {
            synchronizeCompletionFade(completedAt: note?.completedAt)
            updateFormatControlForeground()
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
