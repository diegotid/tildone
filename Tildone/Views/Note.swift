//
//  Note.swift
//  Tildone
//

import CoreTransferable
import SwiftUI
import TildoneDomain
import TildonePersistence
import UniformTypeIdentifiers

struct MacTaskDragPayload: Codable, Hashable, Transferable {
    let noteID: NoteID
    let taskID: TaskID

    func isValid(for noteID: NoteID, taskIDs: [TaskID]) -> Bool {
        self.noteID == noteID && taskIDs.contains(taskID)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

enum MacNoteTitlebarLayout {
    static let titleLeadingInset: CGFloat = 78
    static let trailingMargin: CGFloat = 2
    static let colorPickerWidth: CGFloat = 26
    static let syncIndicatorWidth: CGFloat = 24
    static let controlHeight: CGFloat = 22
    static let controlSpacing: CGFloat = 2
    static let titleControlSpacing: CGFloat = 6

    /// Reserve the maximum title-bar control width so the title neither
    /// overlaps nor jumps when the sync indicator appears or changes state.
    static var titleTrailingInset: CGFloat {
        trailingMargin + colorPickerWidth + controlSpacing + syncIndicatorWidth + titleControlSpacing
    }
}

/// Restart-safe presentation state for a note's destructive completion grace
/// period. The persisted completion date identifies one completion cycle, so a
/// restored or remotely completed note resumes the same fade instead of being
/// treated as permanently "already done."
struct CompletionFadeLifecycle: Equatable {
    enum Phase: Equatable {
        case idle
        case fading(completedAt: Date)
        case cancelled(completedAt: Date)
        case deleting(completedAt: Date)

        var completedAt: Date? {
            switch self {
            case .idle: nil
            case let .fading(completedAt), let .cancelled(completedAt), let .deleting(completedAt):
                completedAt
            }
        }
    }

    private(set) var phase: Phase = .idle

    var isFading: Bool {
        if case .fading = phase { return true }
        return false
    }

    var showsCompletionOverlay: Bool {
        switch phase {
        case .fading, .deleting: true
        case .idle, .cancelled: false
        }
    }

    mutating func synchronize(completedAt: Date?) {
        guard let completedAt else {
            phase = .idle
            return
        }
        guard phase.completedAt != completedAt else { return }
        phase = .fading(completedAt: completedAt)
    }

    mutating func cancel() {
        guard case let .fading(completedAt) = phase else { return }
        phase = .cancelled(completedAt: completedAt)
    }

    func progress(at date: Date, duration: TimeInterval) -> TimeInterval {
        guard case let .fading(completedAt) = phase, duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(completedAt), 0), duration)
    }

    mutating func beginDeletionIfReady(at date: Date, duration: TimeInterval) -> Date? {
        guard case let .fading(completedAt) = phase,
              date.timeIntervalSince(completedAt) >= duration else {
            return nil
        }
        phase = .deleting(completedAt: completedAt)
        return completedAt
    }

    mutating func deletionFailed(completedAt: Date) {
        guard phase == .deleting(completedAt: completedAt) else { return }
        phase = .cancelled(completedAt: completedAt)
    }
}

/// A macOS note window backed solely by shared-domain snapshots. AppKit state
/// (focus, fade, minimization and window styling) deliberately remains here.
struct Note: View {
    @ObservedObject var store: MacSharedStore
    let noteID: NoteID

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TaskLineTruncation.storageKey) private var taskLineTruncation: TaskLineTruncation = .single
    @AppStorage(FontSize.storageKey) private var fontSize = Double(FontSize.small.rawValue)
    @AppStorage(NoteWindowBackground.opacityStorageKey) private var noteBackgroundOpacity = Double(NoteWindowBackground.defaultAlpha)

    private var note: MacNoteSnapshot? { store.note(noteID) }
    private var tasks: [TildoneDomain.Task] { note?.tasks ?? [] }
    private var pendingTasks: [TildoneDomain.Task] { tasks.filter { !$0.isCompleted } }
    private var isDark: Bool { colorScheme == .dark && noteBackgroundOpacity < 0.5 }
    private var noteColor: NoteColor { note?.color ?? .yellow }
    private var color: NSColor { noteColor.nsColor }
    private var isDone: Bool { completionFade.showsCompletionOverlay }

    enum Field: Hashable { case topic, newTask }

    @State private var noteWindow: NSWindow?
    @State private var newTaskText = ""
    @State private var isTextBlurred = false
    @State private var isTopScrolledOut = false
    @State private var isTopicHidden = false
    @State private var didSetInitialFocus = false
    @State private var windowAlpha = 1.0
    @State private var isMinimized = false {
        didSet { setTrafficLightsHidden(isMinimized) }
    }
    @State private var minimizedFromFrame: NSRect?
    @State private var completionFade = CompletionFadeLifecycle()
    @State private var fadeAwayProgress: TimeInterval = 0
    @State private var mutationErrorMessage: String?
    @State private var taskDropFeedbackResetToken = UUID()
    @FocusState private var focusedField: Field?
    @FocusState private var focusedTaskID: TaskID?

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

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
        .onChange(of: noteBackgroundOpacity) { _, _ in applyCurrentNoteBackground() }
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

extension Note {
    func handleMinimize() {
        guard let noteWindow else { return }
        noteWindow.title = "_" + noteWindow.title
        minimizedFromFrame = noteWindow.frame
        withAnimation { isMinimized = true }
        noteWindow.setFrame(minimizedFrame(for: noteWindow), display: true, animate: false)
        NotificationCenter.default.post(name: .arrangeMinimized, object: nil)
    }
}

private extension Note {
    func mutate(_ operation: @escaping () async throws -> Void, message: String) {
        Swift.Task {
            do { try await operation() }
            catch {
                // Repository failures must never terminate the user's note window.
                // In particular, a sync/outbox recovery issue must leave locally
                // persisted content available for an explicit recovery decision.
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: message,
                    error: error
                )
            }
        }
    }

    static func mutationFailureMessage(operation: String, error: Error) -> String {
        var result = "Your notes remain on this Mac. Synchronization needs attention before this change can be saved."
#if DEBUG
        result += "\n\nDevelopment detail: \(operation) / \(safePersistenceCategory(error))"
#endif
        return result
    }

    static func safePersistenceCategory(_ error: Error) -> String {
        guard let error = error as? PersistenceError else { return "non-persistence-error" }
        return switch error {
        case .openFailure: "open-failure"
        case .saveFailure: "save-failure"
        case .missing: "missing-entity"
        case .missingPendingMutation: "missing-pending-mutation"
        case .duplicateID: "duplicate-identifier"
        case .ownershipMismatch: "ownership-mismatch"
        case let .malformedRepresentation(_, _, field): "malformed-\(field)"
        case .domainInvariant: "domain-invariant"
        case .unsupportedRecordSchema: "unsupported-schema"
        case .workspaceMismatch: "workspace-mismatch"
        case .workspaceInUse: "workspace-in-use"
        case .invalidWorkspace: "invalid-workspace"
        case .invalidStoreLocation: "invalid-store-location"
        case .invalidQuarantineMetadata: "invalid-quarantine"
        case .atomicMutationFailure: "atomic-mutation-failure"
        case .counterOverflow: "counter-overflow"
        }
    }

    func handleNewTaskCommit() {
        guard !newTaskText.isEmpty else { return }
        let text = newTaskText.capitalizingFirstLetter()
        newTaskText = ""
        mutate({ _ = try await store.addTask(to: noteID, text: text) }, message: "Error on task creation")
    }

    func handleTaskEdit(_ task: TildoneDomain.Task, to text: String) {
        mutate(
            { try await store.editTask(task.id, text: text.capitalizingFirstLetter()) },
            message: "Error on task edit"
        )
    }

    func handleTaskToggle(_ task: TildoneDomain.Task) {
        noteWindow?.makeFirstResponder(nil)
        mutate({ try await store.setTaskCompletion(task.id, completed: !task.isCompleted) }, message: "Error on task completion")
    }

    func handleTaskDrop(_ payload: MacTaskDragPayload, at destination: Int) -> Bool {
        guard payload.isValid(for: noteID, taskIDs: tasks.map(\.id)),
              (0...tasks.count).contains(destination) else {
            return false
        }
        mutate(
            { _ = try await store.moveTask(payload.taskID, in: noteID, to: destination) },
            message: "Error reordering task"
        )
        DispatchQueue.main.async {
            taskDropFeedbackResetToken = UUID()
        }
        return true
    }

    func handleTopicEdit(to topic: String) {
        let title = topic.isEmpty ? nil : topic.capitalizingFirstLetter()
        mutate({ try await store.renameNote(noteID, to: title) }, message: "Error on topic edit")
    }

    func handleKeyboard() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window == noteWindow else { return event }
            if event.keyCode == Keyboard.tabKey, focusedField == .newTask, !newTaskText.isEmpty {
                handleNewTaskCommit(); return nil
            }
            if event.keyCode == Keyboard.arrowUp { handleMoveUp(); return nil }
            if event.keyCode == Keyboard.arrowDown { handleMoveDown(); return nil }
            if event.keyCode == Keyboard.delete, handleDelete() { return nil }
            if event.keyCode == Keyboard.backSpace, handleDelete(isBackwards: true) { return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                NotificationCenter.default.post(name: .close, object: nil); return nil
            }
            return event
        }
    }

    func handleEnter(for task: TildoneDomain.Task) {
        guard let field = textField(forText: task.text),
              let editor = field.currentEditor() as? NSTextView,
              let cursor = editor.selectedRanges.first?.rangeValue.location,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if cursor == editor.textStorage?.length {
            handleMoveDown()
        } else {
            let insertion = cursor == 0 ? index : index + 1
            mutate({ _ = try await store.addTask(to: noteID, text: "", insertingAt: insertion) }, message: "Error on task creation")
        }
    }

    func handleMoveUp() {
        guard let id = focusedTaskID, let index = pendingTasks.firstIndex(where: { $0.id == id }) else {
            if focusedField == .newTask { focusedTaskID = pendingTasks.last?.id } else { focusOnNewTask() }
            return
        }
        if index > 0 { focusedTaskID = pendingTasks[index - 1].id } else { focusOnTopic() }
    }

    func handleMoveDown() {
        guard let id = focusedTaskID, let index = pendingTasks.firstIndex(where: { $0.id == id }) else {
            if focusedField == .topic { focusedTaskID = pendingTasks.first?.id } else { focusOnTopic() }
            return
        }
        if index < pendingTasks.endIndex - 1 { focusedTaskID = pendingTasks[index + 1].id } else { focusOnNewTask() }
    }

    func handleDelete(isBackwards: Bool = false) -> Bool {
        guard let id = focusedTaskID, let index = pendingTasks.firstIndex(where: { $0.id == id }), pendingTasks[index].text.isEmpty else {
            return false
        }
        let next = index - (isBackwards ? 1 : 0)
        mutate({ try await store.deleteTask(id) }, message: "Error on task deletion")
        if !pendingTasks.isEmpty { focusedTaskID = pendingTasks[max(0, min(next, pendingTasks.count - 1))].id }
        return true
    }

    func paste(into task: TildoneDomain.Task) {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
        let lines = clipboard.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        guard let first = lines.first, let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        mutate({
            try await store.editTask(task.id, text: first)
            for line in lines.dropFirst().reversed() {
                _ = try await store.addTask(to: noteID, text: line.capitalizingFirstLetter(), insertingAt: index + 1)
            }
        }, message: "Error pasting tasks")
    }

    func handleBringUp() {
        guard let noteWindow, noteWindow.title.starts(with: "_"), let frame = minimizedFromFrame else { return }
        noteWindow.title = String(noteWindow.title.dropFirst())
        minimizedFromFrame = nil
        DispatchQueue.main.async {
            withAnimation { noteWindow.setFrame(frame, display: true, animate: true) } completion: {
                withAnimation { isMinimized = false }
            }
        }
    }

    func cleanIfRequested(_ notification: Notification) {
        guard let id = notification.object as? NoteID, id == noteID else { return }
        mutate({ try await store.cleanEmptyTasks(in: noteID) }, message: "Error cleaning note")
    }

    func synchronizeCompletionFade(completedAt: Date?) {
        completionFade.synchronize(completedAt: completedAt)
        updateTopicVisibility()
        if completionFade.isFading {
            advanceCompletionFade(Date())
        } else if !completionFade.showsCompletionOverlay {
            resetFadeAppearance()
        }
    }

    func advanceCompletionFade(_ date: Date) {
        guard completionFade.isFading else { return }
        fadeAwayProgress = completionFade.progress(
            at: date,
            duration: Timeout.noteFadeOutSeconds
        )
        updateFadeAppearance()
        guard let completedAt = completionFade.beginDeletionIfReady(
            at: date,
            duration: Timeout.noteFadeOutSeconds
        ) else { return }
        deleteCompletedNote(completedAt: completedAt)
    }

    func cancelCompletionFade() {
        completionFade.cancel()
        updateTopicVisibility()
        resetFadeAppearance()
    }

    func deleteCompletedNote(completedAt: Date) {
        guard note?.completedAt == completedAt else {
            synchronizeCompletionFade(completedAt: note?.completedAt)
            return
        }
        Swift.Task {
            do {
                try await store.deleteNote(noteID)
            } catch {
                completionFade.deletionFailed(completedAt: completedAt)
                resetFadeAppearance()
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error deleting completed note",
                    error: error
                )
            }
        }
    }

    func resetFadeAppearance() {
        fadeAwayProgress = 0
        updateFadeAppearance()
    }

    func updateFadeAppearance() {
        windowAlpha = max(0, 1 - fadeAwayProgress / Timeout.noteFadeOutSeconds)
        let disappearing = windowAlpha < 1
        withAnimation {
            noteWindow?.level = disappearing ? .normal : .floating
            noteWindow?.hasShadow = !disappearing
            setTrafficLightsHidden(disappearing || isMinimized)
            applyCurrentNoteBackground()
        }
    }

    func setTrafficLightsHidden(_ hidden: Bool) {
        noteWindow?.standardWindowButton(.closeButton)?.isHidden = hidden
        noteWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = hidden
        noteWindow?.standardWindowButton(.zoomButton)?.isHidden = hidden
    }

    func updateWindowClosability() {
        noteWindow?.standardWindowButton(.closeButton)?.isEnabled = note?.isDeletable ?? false
    }

    func updateTopicVisibility() {
        withAnimation { isTopicHidden = (note?.title == nil) && (isDone || focusedField != .topic) }
    }

    func applyCurrentNoteBackground() {
        noteWindow?.applyNoteBackgroundColor(color, alpha: CGFloat(noteBackgroundOpacity * windowAlpha))
    }

    func applyInitialFocusIfNeeded() {
        guard !didSetInitialFocus, let note, note.tasks.isEmpty, note.title == nil, noteWindow != nil else { return }
        didSetInitialFocus = true
        DispatchQueue.main.async { focusOnTopic() }
    }

    func convertLegacyFontSizeSettingIfNeeded() {
        if fontSize < FontSize.xSmall.rawValue, let size = FontSize(fromLegacySetting: fontSize) { fontSize = size.rawValue }
    }

    func focusOnTopic() { focusedTaskID = nil; focusedField = .topic }
    func focusOnNewTask() { focusedTaskID = nil; focusedField = .newTask }

    func placeCursor(forText value: String, at position: Int = 0) {
        textField(forText: value)?.currentEditor()?.selectedRange = NSMakeRange(position, position)
    }

    func textField(forText value: String) -> NSTextField? {
        noteWindow?.contentView?.getNestedSubviews().first(where: { $0.stringValue == value })
    }

    func minimizedFrame(for window: NSWindow) -> NSRect {
        let content = NSRect(origin: .zero, size: NSSize(width: Layout.minimizedNoteWidth, height: Layout.minimizedNoteHeight))
        let frame = window.frameRect(forContentRect: content)
        return NSRect(x: window.frame.minX, y: window.frame.maxY - frame.height, width: frame.width, height: frame.height)
    }
}

private extension Note {
    func taskList(_ note: MacNoteSnapshot) -> some View {
        ZStack {
            Group {
                ScrollViewReader { scroll in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            topicListItem()
                            taskDropTarget(at: 0)
                            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                taskRow(task, at: index)
                                taskDropTarget(at: index + 1)
                            }
                            newListItem().opacity(isDone || isTextBlurred ? 0 : 1)
                            Spacer().id(Id.bottomAnchor)
                        }
                        .onAppear {
                            if note.title == nil { focusOnTopic() } else { focusOnNewTask() }
                            applyInitialFocusIfNeeded()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .minimizeAll)) { _ in handleMinimize() }
                    }
                    .modifier(ScrollFrame())
                    .onChange(of: tasks.count) { _, _ in withAnimation { scroll.scrollTo(Id.bottomAnchor, anchor: .bottom) } }
                }
                if isTopScrolledOut { scrollingHeader() }
            }
            .blur(radius: isTextBlurred ? 3 : 0)
            .opacity(windowAlpha / (isDone ? 2 : 1))
            if isDone { doneOverlay() }
        }
        .frame(minWidth: Layout.minNoteWidth, idealWidth: Layout.defaultNoteWidth, maxWidth: .infinity,
               minHeight: Layout.minNoteHeight, idealHeight: Layout.defaultNoteHeight, maxHeight: .infinity)
        .background(WindowAccessor(note: Binding.constant(self), window: $noteWindow))
        .onAppear {
            handleKeyboard()
            convertLegacyFontSizeSettingIfNeeded()
            applyInitialFocusIfNeeded()
        }
        .onChange(of: noteWindow) { _, _ in
            applyInitialFocusIfNeeded()
            if completionFade.isFading {
                advanceCompletionFade(Date())
            } else {
                updateFadeAppearance()
            }
        }
        .onChange(of: note.isDeletable) { _, _ in updateWindowClosability() }
        .onReceive(NotificationCenter.default.publisher(for: .visibility)) { notification in
            if let (blur, normal) = notification.object as? (Bool, Bool) {
                noteWindow?.level = normal ? .normal : .floating
                isTextBlurred = blur
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clean), perform: cleanIfRequested)
        .disabled(isTextBlurred)
    }

    func taskListProgress(_ note: MacNoteSnapshot) -> some View {
        let pending = note.pendingTasks.count
        let total = note.tasks.count
        let complete = pending == 0 && total > 0
        let foreground = complete ? Color.accentColor : isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)
        return VStack {
            if let title = note.title {
                Text(title).font(.system(size: 12)).foregroundStyle(foreground).bold().lineLimit(1)
                    .padding(.top, -32).padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
            Gauge(value: total == 0 ? 0 : Float(total - pending), in: 0...Float(max(total, 1))) {
                Text(statusText(complete: complete, total: total)).font(.system(size: 10)).foregroundStyle(foreground)
            } currentValueLabel: {
                Text("\(pending)").bold().font(.system(size: 30)).foregroundStyle(foreground)
            }
            .gaugeStyle(.accessoryCircular).tint(Gradient(colors: [.clear, foreground]))
        }
        .frame(width: Layout.minimizedNoteWidth, height: Layout.minimizedNoteHeight)
        .background(WindowAccessor(note: Binding.constant(self), window: $noteWindow))
        .onTapGesture(perform: handleBringUp)
        .onReceive(NotificationCenter.default.publisher(for: .bringAllUp)) { _ in handleBringUp() }
    }

    private func statusText(complete: Bool, total: Int) -> String {
        if complete { return String(localized: "all done") }
        if total == 0 { return String(localized: "no tasks") }
        return String(localized: "pending")
    }

    func listTopic() -> some View {
        let size = 20 / CGFloat(FontSize.small.rawValue) * CGFloat(fontSize)
        return GeometryReader { geometry in
            TextField("Topic", text: Binding(get: { note?.title ?? "" }, set: handleTopicEdit))
                .textFieldStyle(.plain).truncationMode(.tail).font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundColor(isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).background(Color.clear).padding(.top, 5)
                .focused($focusedField, equals: .topic)
                .onChange(of: focusedField) { _, field in
                    if let title = note?.title, field == .topic { placeCursor(forText: title) }
                    updateTopicVisibility()
                }
                .onSubmit { tasks.isEmpty ? focusOnNewTask() : handleMoveDown() }
                .onChange(of: geometry.frame(in: .global)) { _, frame in withAnimation(.easeInOut) { isTopScrolledOut = frame.minY < 10 } }
                .onHover { hovering in if hovering { isTopicHidden = false } else { updateTopicVisibility() } }
        }
        .padding(.bottom, size)
    }

    func scrollingHeader() -> some View {
        VStack {
            ZStack {
                Color.clear
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.black.opacity(0.2)).frame(height: 1)
                    }
                if let title = note?.title {
                    HStack(spacing: 0) {
                        Text(title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, MacNoteTitlebarLayout.titleLeadingInset)
                    .padding(.trailing, MacNoteTitlebarLayout.titleTrailingInset)
                    .offset(y: -1)
                }
            }
            Spacer()
        }.padding(.top, -30)
    }

    func newListItem() -> some View {
        HStack(spacing: 8) {
            Checkbox().disabled(true)
            ZStack(alignment: .leading) {
                if newTaskText.isEmpty { Text("New task").font(.system(size: CGFloat(fontSize))).foregroundColor(isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).opacity(0.6).allowsHitTesting(false) }
                TextField("", text: $newTaskText).textFieldStyle(.plain).font(.system(size: CGFloat(fontSize))).foregroundColor(isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor))
                    .onSubmit { handleNewTaskCommit() }.focused($focusedField, equals: .newTask)
                    .onChange(of: focusedField) { _, field in if field != .newTask && !newTaskText.isEmpty { handleNewTaskCommit() } }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in handleNewTaskCommit() }
            }
            Spacer()
        }.padding(.leading, 2).padding(.bottom, 10)
    }

    func topicListItem() -> some View {
        listTopic()
            .opacity(isTopScrolledOut || isTopicHidden ? 0 : 1)
            .frame(height: isTopicHidden ? 1 : 30)
            .padding(.bottom, CGFloat(fontSize - 10))
    }

    func taskRow(_ task: TildoneDomain.Task, at index: Int) -> TaskRow {
        TaskRow(
            task: task,
            dragPayload: MacTaskDragPayload(noteID: noteID, taskID: task.id),
            rowIndex: index,
            fontSize: fontSize,
            isDark: isDark,
            truncation: taskLineTruncation,
            isFirst: task.id == tasks.first?.id,
            feedbackResetToken: taskDropFeedbackResetToken,
            focusedTaskID: $focusedTaskID,
            onToggle: { handleTaskToggle(task) },
            onEdit: { handleTaskEdit(task, to: $0) },
            onFocus: { placeCursor(forText: task.text) },
            onEnter: { handleEnter(for: task) },
            onCopy: { Copier.copy(task.text, forType: .string) },
            onPaste: { paste(into: task) },
            onSubmit: handleMoveDown,
            onDrop: { payload, destination in
                handleTaskDrop(payload, at: destination)
            },
            onHover: { hovering in
                if hovering { isTopicHidden = false } else { updateTopicVisibility() }
            }
        )
    }

    func taskDropTarget(at destination: Int) -> TaskReorderDropTarget {
        TaskReorderDropTarget(feedbackResetToken: taskDropFeedbackResetToken) { payload in
            handleTaskDrop(payload, at: destination)
        }
    }

    func doneOverlay() -> some View {
        VStack {
            Spacer()
            Image(systemName: "checkmark").padding(.top, 12).padding(.leading, 12).font(.system(size: 90, weight: .bold)).foregroundColor(.accentColor).symbolEffect(.bounce, value: completionFade.isFading)
            Text("Done!").padding(.leading, 6).padding(.bottom, completionFade.isFading ? 30 : 60).font(.system(size: 30, weight: .bold)).foregroundColor(.accentColor)
            Spacer()
            if completionFade.isFading {
                ZStack {
                    ProgressView("Fading out...", value: fadeAwayProgress, total: Timeout.noteFadeOutSeconds).foregroundColor(.accentColor).padding(.horizontal, 20).padding(.bottom, 12)
                    HStack { Spacer(); Button("Cancel", action: cancelCompletionFade).buttonStyle(.plain).padding(.trailing, 20).padding(.bottom, 30) }
                }
            }
        }.opacity(windowAlpha * 0.9)
    }
}

enum MacNoteSyncIndicatorState: Equatable {
    case hidden
    case onlyOnThisMac
    case attentionNeeded

    static func resolve(
        isUsingNotesOnMacByChoice: Bool,
        syncNeedsAttention: Bool
    ) -> MacNoteSyncIndicatorState {
        if syncNeedsAttention { return .attentionNeeded }
        return isUsingNotesOnMacByChoice ? .onlyOnThisMac : .hidden
    }

    var symbolName: String {
        switch self {
        case .hidden: "icloud"
        case .onlyOnThisMac: "icloud.slash"
        case .attentionNeeded: "exclamationmark.icloud"
        }
    }

    var status: String {
        switch self {
        case .hidden: ""
        case .onlyOnThisMac:
            String(localized: "Only on this Mac — not syncing with iPhone or iCloud.")
        case .attentionNeeded:
            String(localized: "Not syncing with iCloud right now. Your notes are safe on this Mac.")
        }
    }

    var accessibilityHelp: String {
        switch self {
        case .hidden: ""
        case .onlyOnThisMac: String(localized: "Review Options…")
        case .attentionNeeded: String(localized: "Sync Status…")
        }
    }

    var actionNotification: Notification.Name? {
        switch self {
        case .hidden: nil
        case .onlyOnThisMac: .openSyncResolutionOptions
        case .attentionNeeded: .openSyncStatus
        }
    }
}

final class MacNoteSyncTitlebarControl: NSHostingView<MacNoteSyncTitlebarIcon> {
    private let state: MacNoteSyncIndicatorState

    required init(rootView: MacNoteSyncTitlebarIcon) {
        state = rootView.state
        super.init(rootView: rootView)
        toolTip = state.status
        setAccessibilityElement(true)
        setAccessibilityLabel(state.status)
        setAccessibilityHelp(state.accessibilityHelp)
        setAccessibilityRole(.button)
    }

    convenience init(state: MacNoteSyncIndicatorState) {
        self.init(rootView: MacNoteSyncTitlebarIcon(state: state))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        openOptions()
    }

    override func accessibilityPerformPress() -> Bool {
        openOptions()
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    private func openOptions() {
        guard let actionNotification = state.actionNotification else { return }
        NotificationCenter.default.post(name: actionNotification, object: nil)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

struct MacNoteSyncTitlebarIcon: View {
    let state: MacNoteSyncIndicatorState

    var body: some View {
        Image(systemName: state.symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(state == .attentionNeeded
                ? Color(nsColor: .systemOrange)
                : Color(nsColor: .secondaryLabelColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}

final class NoteColorPickerTitlebarControl: NSHostingView<NoteColorPickerTitlebarIcon> {
    private let store: MacSharedStore
    private let noteID: NoteID
    private let popover = NSPopover()

    required init(rootView: NoteColorPickerTitlebarIcon) {
        store = rootView.store
        noteID = rootView.noteID
        super.init(rootView: rootView)
        toolTip = "Note color"
        setAccessibilityLabel("Note color")
        setAccessibilityRole(.button)
        popover.behavior = .transient
    }

    convenience init(store: MacSharedStore, noteID: NoteID) {
        self.init(rootView: NoteColorPickerTitlebarIcon(store: store, noteID: noteID))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        togglePopover()
    }

    override func accessibilityPerformPress() -> Bool {
        togglePopover()
        return true
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        let controller = NSViewController()
        let paletteView = NSHostingView(
            rootView: NoteColorPickerTitlebarPalette(store: store, noteID: noteID) { [weak self] in
                self?.popover.performClose(nil)
            }
            .fixedSize()
        )
        let paletteSize = NSSize(width: 126, height: 80)
        paletteView.frame = NSRect(origin: .zero, size: paletteSize)
        controller.view = paletteView
        popover.contentViewController = controller
        popover.contentSize = paletteSize

        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

struct NoteColorPickerTitlebarIcon: View {
    @ObservedObject var store: MacSharedStore
    let noteID: NoteID

    var body: some View {
        NoteColorPickerIcon(color: store.note(noteID)?.color ?? .yellow)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}

private struct NoteColorPickerTitlebarPalette: View {
    @ObservedObject var store: MacSharedStore
    let noteID: NoteID
    let dismiss: () -> Void

    var body: some View {
        NoteColorPalette(selected: store.note(noteID)?.color ?? .yellow) { selectedColor in
            Swift.Task { try? await store.setColor(selectedColor, for: noteID) }
            dismiss()
        }
    }
}

private struct NoteColorPickerIcon: View {
    let color: NoteColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .padding(3)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.15), lineWidth: 0.5)
                        .padding(3)
                }
        }
        .frame(width: 16, height: 16)
    }
}

private struct NoteColorPalette: View {
    let selected: NoteColor
    let onSelect: (NoteColor) -> Void

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NoteColor.allCases) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .stroke(
                                    selected == color ? Color.accentColor : .black.opacity(0.18),
                                    lineWidth: selected == color ? 3 : 0.75
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(color.localizedLabel)
                .accessibilityLabel(color.localizedLabel)
                .accessibilityAddTraits(selected == color ? .isSelected : [])
            }
        }
        .padding(10)
    }
}

struct ScrollFrame: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.top, 0).padding(.trailing, 5).padding(.leading, 20).colorScheme(.light)
    }
}

private struct TaskRow: View {
    let task: TildoneDomain.Task
    let dragPayload: MacTaskDragPayload
    let rowIndex: Int
    let fontSize: Double
    let isDark: Bool
    let truncation: TaskLineTruncation
    let isFirst: Bool
    let feedbackResetToken: UUID
    @FocusState.Binding var focusedTaskID: TaskID?
    @State private var rowHeight: CGFloat = 0
    @State private var dropPlacement: TaskRowDropPlacement?
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onSubmit: () -> Void
    let onDrop: (MacTaskDragPayload, Int) -> Bool
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Checkbox(checked: task.isCompleted)
                .disabled(task.text.isEmpty)
                .onToggle { onToggle() }
                .padding(.vertical, 2.4)

            if task.isCompleted {
                Text(task.text)
                    .font(.system(size: CGFloat(fontSize)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(
                        isDark
                            ? Color(.primaryFontWhite).opacity(0.6)
                            : Color(.primaryFontColor).opacity(0.6)
                    )
                    .overlay {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .offset(y: 1)
                    }
            } else {
                TextField(
                    "New task.default",
                    text: Binding(get: { task.text }, set: onEdit),
                    axis: truncation == .single ? .horizontal : .vertical
                )
                .if(truncation == .single) { $0.truncationMode(.tail) }
                .textFieldStyle(.plain)
                .font(.system(size: CGFloat(fontSize)))
                .foregroundColor(isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor))
                .background(Color.clear)
                .focused($focusedTaskID, equals: task.id)
                .onChange(of: focusedTaskID) { _, id in
                    if id == task.id { onFocus() }
                }
                .onKeyPress(keys: [.return]) { _ in
                    onEnter()
                    return .handled
                }
                .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                    if focusedTaskID == task.id { onCopy() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                    if focusedTaskID == task.id { onPaste() }
                }
                .onSubmit { onSubmit() }
            }

            Spacer()

            TaskReorderHandle(
                payload: dragPayload,
                taskText: task.text,
                isCompleted: task.isCompleted,
                fontSize: fontSize,
                isDark: isDark
            )
            .padding(.trailing, 8)
        }
        .padding(.leading, 2)
        .if(isFirst) { $0.onHover { onHover($0) } }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rowHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in rowHeight = height }
            }
        }
        .padding(.top, dropPlacement == .before ? TaskReorderFeedback.insertionSpacing : 0)
        .padding(.bottom, dropPlacement == .after ? TaskReorderFeedback.insertionSpacing : 0)
        .background(alignment: dropPlacement == .before ? .top : .bottom) {
            TaskReorderInsertionLine()
                .opacity(dropPlacement == nil ? 0 : 1)
                .offset(
                    y: dropPlacement == .before
                        ? TaskReorderFeedback.insertionSpacing / 2
                        : -TaskReorderFeedback.insertionSpacing / 2
                )
        }
        .animation(TaskReorderFeedback.animation, value: dropPlacement)
        .onChange(of: feedbackResetToken) { _, _ in
            dropPlacement = nil
        }
        .onDrop(
            of: [.json],
            delegate: TaskRowDropDelegate(
                rowIndex: rowIndex,
                rowHeight: rowHeight,
                placement: $dropPlacement,
                onDrop: onDrop
            )
        )
    }
}

private struct TaskReorderInsertionLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 2)
            .allowsHitTesting(false)
    }
}

private enum TaskReorderFeedback {
    static let restingHeight: CGFloat = 6
    static let insertionSpacing: CGFloat = 18
    static let expandedHeight = restingHeight + insertionSpacing
    static let animation = Animation.easeInOut(duration: 0.16)
}

private enum TaskRowDropPlacement {
    case before
    case after
}

private struct TaskRowDropDelegate: DropDelegate {
    let rowIndex: Int
    let rowHeight: CGFloat
    @Binding var placement: TaskRowDropPlacement?
    let onDrop: (MacTaskDragPayload, Int) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.itemProviders(for: [.json]).count == 1
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        placement = placement(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        placement = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.json])
        guard providers.count == 1, let provider = providers.first else {
            placement = nil
            return false
        }

        let destination = destination(for: placement(at: info.location))
        placement = nil
        provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
            guard let data,
                  let payload = try? JSONDecoder().decode(MacTaskDragPayload.self, from: data) else {
                return
            }
            DispatchQueue.main.async {
                _ = onDrop(payload, destination)
            }
        }
        return true
    }

    private func placement(at location: CGPoint) -> TaskRowDropPlacement {
        let topInset = placement == .before ? TaskReorderFeedback.insertionSpacing : 0
        return location.y - topInset < rowHeight / 2 ? .before : .after
    }

    private func destination(for placement: TaskRowDropPlacement) -> Int {
        placement == .before ? rowIndex : rowIndex + 1
    }
}

struct TaskReorderHandle: View {
    let payload: MacTaskDragPayload
    let taskText: String
    let isCompleted: Bool
    let fontSize: Double
    let isDark: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).opacity(0.45)
            )
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .accessibilityLabel("Reorder task")
            .draggable(payload) {
                TaskReorderPreview(
                    taskText: taskText,
                    isCompleted: isCompleted,
                    fontSize: fontSize,
                    isDark: isDark
                )
            }
    }
}

private struct TaskReorderPreview: View {
    let taskText: String
    let isCompleted: Bool
    let fontSize: Double
    let isDark: Bool

    var body: some View {
        HStack(spacing: 8) {
            Checkbox(checked: isCompleted)
                .disabled(true)

            Text(taskText.isEmpty ? String(localized: "Untitled task") : taskText)
                .font(.system(size: CGFloat(fontSize)))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(
                    (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor))
                        .opacity(isCompleted ? 0.6 : 1)
                )
                .overlay {
                    if isCompleted {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .offset(y: 1)
                    }
                }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).opacity(0.45)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, isDark ? .dark : .light)
    }
}

struct TaskReorderDropTarget: View {
    let feedbackResetToken: UUID
    let onDrop: (MacTaskDragPayload) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(
                height: isTargeted
                    ? TaskReorderFeedback.expandedHeight
                    : TaskReorderFeedback.restingHeight
            )
            .contentShape(Rectangle())
            .background {
                TaskReorderInsertionLine()
                    .opacity(isTargeted ? 1 : 0)
            }
            .dropDestination(for: MacTaskDragPayload.self) { payloads, _ in
                guard payloads.count == 1, let payload = payloads.first else { return false }
                return onDrop(payload)
            } isTargeted: {
                isTargeted = $0
            }
            .animation(TaskReorderFeedback.animation, value: isTargeted)
            .onChange(of: feedbackResetToken) { _, _ in
                isTargeted = false
            }
    }
}
