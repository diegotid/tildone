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

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TaskLineTruncation.storageKey) private var taskLineTruncation: TaskLineTruncation = .single
    @AppStorage(FontSize.storageKey) private var fontSize = Double(FontSize.small.rawValue)
    @AppStorage(NoteColor.storageKey) private var noteColor: NoteColor = .yellow
    @AppStorage(NoteWindowBackground.opacityStorageKey) private var noteBackgroundOpacity = Double(NoteWindowBackground.defaultAlpha)

    private var note: MacNoteSnapshot? { store.note(noteID) }
    private var tasks: [TildoneDomain.Task] { note?.tasks ?? [] }
    private var pendingTasks: [TildoneDomain.Task] { tasks.filter { !$0.isCompleted } }
    private var isDark: Bool { colorScheme == .dark && noteBackgroundOpacity < 0.5 }
    private var color: NSColor { noteColor.nsColor }

    enum Field: Hashable { case topic, newTask }

    @State private var noteWindow: NSWindow?
    @State private var newTaskText = ""
    @State private var isTextBlurred = false
    @State private var isTopScrolledOut = false
    @State private var isTopicHidden = false
    @State private var didSetInitialFocus = false
    @State private var wasAlreadyDone = false
    @State private var isDone = false
    @State private var windowAlpha = 1.0
    @State private var isMinimized = false {
        didSet { setTrafficLightsHidden(isMinimized) }
    }
    @State private var minimizedFromFrame: NSRect?
    @State private var isFadingAway = false
    @State private var fadeAwayProgress: Float = 0 {
        didSet { updateFade() }
    }
    @FocusState private var focusedField: Field?
    @FocusState private var focusedTaskID: TaskID?

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

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
        .onChange(of: noteColor) { _, _ in applyCurrentNoteBackground() }
        .onChange(of: noteBackgroundOpacity) { _, _ in applyCurrentNoteBackground() }
        .onChange(of: note?.isComplete ?? false) { _, complete in
            guard newTaskText.isEmpty else { return }
            setCompletionState(complete)
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
            catch { fatalError("\(message): \(error)") }
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

    func handleDisappearance() {
        mutate({ try await store.deleteNote(noteID) }, message: "Error deleting completed note")
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

    func setCompletionState(_ complete: Bool) {
        isDone = complete
        updateTopicVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if !wasAlreadyDone { isFadingAway = complete }
        }
    }

    func updateFade() {
        windowAlpha = 1 - Double(fadeAwayProgress / Timeout.noteFadeOutSeconds)
        let disappearing = windowAlpha < 1
        withAnimation {
            noteWindow?.level = disappearing ? .normal : .floating
            noteWindow?.hasShadow = !disappearing
            setTrafficLightsHidden(disappearing)
            applyCurrentNoteBackground()
        }
        if fadeAwayProgress >= Timeout.noteFadeOutSeconds {
            noteWindow?.close()
            handleDisappearance()
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
                        VStack(spacing: 6) {
                            topicListItem()
                            ForEach(tasks, id: \.id) { task in
                                taskRow(task)
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
            isDone = note.isComplete
            wasAlreadyDone = note.isComplete
            convertLegacyFontSizeSettingIfNeeded()
            applyInitialFocusIfNeeded()
        }
        .onChange(of: noteWindow) { _, _ in applyInitialFocusIfNeeded() }
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
                Text(complete ? "all done" : total == 0 ? "no tasks" : "pending").font(.system(size: 10)).foregroundStyle(foreground)
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
                Rectangle().fill(Color(nsColor: color.withAlphaComponent(windowAlpha))).frame(height: 30).shadow(color: .black.opacity(0.2), radius: 1.5, x: 0, y: 1)
                if let title = note?.title {
                    HStack { Text(title).lineLimit(1).font(.system(size: 14, weight: .bold, design: .rounded)).padding(.leading, 70); Spacer() }
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

    func taskRow(_ task: TildoneDomain.Task) -> TaskRow {
        TaskRow(
            task: task,
            fontSize: fontSize,
            isDark: isDark,
            truncation: taskLineTruncation,
            isFirst: task.id == tasks.first?.id,
            focusedTaskID: $focusedTaskID,
            onToggle: { handleTaskToggle(task) },
            onEdit: { handleTaskEdit(task, to: $0) },
            onFocus: { placeCursor(forText: task.text) },
            onEnter: { handleEnter(for: task) },
            onCopy: { Copier.copy(task.text, forType: .string) },
            onPaste: { paste(into: task) },
            onSubmit: handleMoveDown,
            onHover: { hovering in
                if hovering { isTopicHidden = false } else { updateTopicVisibility() }
            }
        )
    }

    func doneOverlay() -> some View {
        VStack {
            Spacer()
            Image(systemName: "checkmark").padding(.top, 12).padding(.leading, 12).font(.system(size: 90, weight: .bold)).foregroundColor(.accentColor).symbolEffect(.bounce, value: isFadingAway)
            Text("Done!").padding(.leading, 6).padding(.bottom, wasAlreadyDone ? 60 : 30).font(.system(size: 30, weight: .bold)).foregroundColor(.accentColor)
            Spacer()
            if !wasAlreadyDone {
                ZStack {
                    ProgressView("Fading out...", value: fadeAwayProgress, total: Timeout.noteFadeOutSeconds).foregroundColor(.accentColor).padding(.horizontal, 20).padding(.bottom, 12)
                        .onReceive(timer) { _ in if fadeAwayProgress < Timeout.noteFadeOutSeconds { fadeAwayProgress += 0.05 } }
                    HStack { Spacer(); Button("Cancel") { isDone = false; fadeAwayProgress = 0 }.buttonStyle(.plain).padding(.trailing, 20).padding(.bottom, 30) }
                }
            }
        }.opacity(windowAlpha * 0.9)
    }
}

struct ScrollFrame: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.top, 0).padding(.trailing, 5).padding(.leading, 20).colorScheme(.light)
    }
}

private struct TaskRow: View {
    let task: TildoneDomain.Task
    let fontSize: Double
    let isDark: Bool
    let truncation: TaskLineTruncation
    let isFirst: Bool
    @FocusState.Binding var focusedTaskID: TaskID?
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    let onFocus: () -> Void
    let onEnter: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onSubmit: () -> Void
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
        }
        .padding(.leading, 2)
        .if(isFirst) { $0.onHover { onHover($0) } }
    }
}
