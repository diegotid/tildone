//
//  Note.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import SwiftData

// MARK: Note view

struct Note: View {
    @Environment(\.license) private var license
    @Environment(\.modelContext) private var modelContext
    @AppStorage("taskLineTruncation") private var taskLineTruncation: TaskLineTruncation = .single
    @AppStorage("fontSize") private var fontSize = Double(FontSize.small.rawValue)
    
    var list: TodoList?
    var sortedTasks: [Todo] {
        let tasks = list?.items ?? []
        return tasks.sorted()
    }
    var sortedPendingTasks: [Todo] {
        let tasks = list?.items ?? []
        let pending = tasks.filter({ $0.done == nil })
        return pending.sorted()
    }

    enum Field: Hashable {
        case topic
        case task
        case newTask
    }
    @State private var noteWindow: NSWindow?
    @State private var newTaskText: String = ""
    @State private var isTextBlurred: Bool = false
    @State private var isTopScrolledOut: Bool = false
    @State private var isTopicHidden: Bool = false
    @State private var isTopicEmpty: Bool = false {
        didSet { updateTopicVisibility() }
    }
    @FocusState private var focusedField: Field?
    @FocusState private var focusedTaskDate: Date?

    private var timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private var color: NSColor {
        list?.isSystemList ?? false ? .systemNoteBackground : .noteBackground
    }

    @State private var wasAlreadyDone: Bool = false
    @State private var isDone: Bool = false {
        didSet {
            updateTopicVisibility()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !wasAlreadyDone {
                    self.isFadingAway = isDone
                }
            }
        }
    }
    @State private var windowAlpha: Double = 1
    @State private var isMinimized: Bool = false {
        didSet {
            noteWindow?.standardWindowButton(.closeButton)?.isHidden = isMinimized
            noteWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = isMinimized
            noteWindow?.standardWindowButton(.zoomButton)?.isHidden = isMinimized
        }
    }
    @State private var minimizedFromFrame: NSRect? = nil
    @State private var isFadingAway: Bool = false
    @State private var fadeAwayProgress: Float = 0.0 {
        didSet {
            windowAlpha = 1.0 - Double(fadeAwayProgress / Timeout.noteFadeOutSeconds)
            let hasDiessapeared: Bool = fadeAwayProgress >= Timeout.noteFadeOutSeconds
            let isDisappearing: Bool = windowAlpha < 1.0
            withAnimation {
                noteWindow?.level = isDisappearing ? .normal : .floating
                noteWindow?.hasShadow = isDisappearing ? false : true
                noteWindow?.standardWindowButton(.closeButton)?.isHidden = isDisappearing
                noteWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = isDisappearing
                noteWindow?.standardWindowButton(.zoomButton)?.isHidden = isDisappearing
                noteWindow?.backgroundColor = self.color.withAlphaComponent(windowAlpha)
            }
            if hasDiessapeared {
                noteWindow?.close()
                handleDisappearance()
            }
        }
    }
    
    var body: some View {
        if let list = self.list {
            if isMinimized {
                taskListProgess(list)
            } else {
                taskList(list)
            }
        }
    }
}

// MARK: Note parameters

extension Note {
    
    func todoList(_ list: TodoList) -> Self {
        var modified: Note = self
        modified.list = list
        return modified
    }
}

// MARK: Public note event handlers

extension Note {
    
    func handleMinimize() {
        if let window = self.noteWindow {
            window.title = "_" + window.title
            self.minimizedFromFrame = window.frame
            NotificationCenter.default.post(name: .arrangeMinimized, object: nil)
            withAnimation {
                self.isMinimized = true
            } completion: {
                NotificationCenter.default.post(name: .arrangeMinimized, object: nil)
            }
        }
    }
}

// MARK: Note event handlers

private extension Note {
    
    func handleNewTaskCommit() {
        guard let list = self.list,
              !newTaskText.isEmpty else {
            return
        }
        list.createNewTask(todo: newTaskText, at: 1 + list.items.count)
        self.newTaskText = ""
        updateWindowClosability()
    }
    
    func handleTaskEdit(_ task: Todo, to what: String) {
        task.what = what.capitalizingFirstLetter()
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task edit: \(error)")
        }
    }
    
    func handleTaskToggle(_ task: Todo) {
        task.setDone(!task.isDone)
        updateWindowClosability()
        do {
            try modelContext.save()
            guard newTaskText.isEmpty else {
                return
            }
            withAnimation {
                self.isDone = list?.isComplete ?? false
            }
        } catch {
            fatalError("Error on task edit: \(error)")
        }
    }
    
    func handleTopicEdit(to topic: String) {
        guard let list = self.list else {
            return
        }
        isTopicEmpty = topic.isEmpty
        if isTopicEmpty {
            list.topic = nil
        } else {
            list.topic = topic.capitalizingFirstLetter()
        }
        do {
            try modelContext.save()
            updateWindowClosability()
        } catch {
            fatalError("Error on topic edit: \(error)")
        }
    }
    
    func handleKeyboard() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
            guard event.window == noteWindow else {
                return event
            }
            if event.keyCode == Keyboard.tabKey
                && focusedField == .newTask
                && !newTaskText.isEmpty {
                handleNewTaskCommit()
                return nil
            } else if event.keyCode == Keyboard.arrowUp {
                handleMoveUp()
                return nil
            } else if event.keyCode == Keyboard.arrowDown {
                handleMoveDown()
                return nil
            } else if event.keyCode == Keyboard.delete {
                let hasBeenDeleted: Bool = handleDelete()
                return hasBeenDeleted ? nil : event
            } else if event.keyCode == Keyboard.backSpace {
                let hasBeenDeleted: Bool = handleDelete(isBackwards: true)
                return hasBeenDeleted ? nil : event
            } else if event.modifierFlags.contains(.command),
                      event.charactersIgnoringModifiers == "w" {
                NotificationCenter.default.post(name: .close, object: nil)
                return nil
            } else {
                return event
            }
        }
    }
    
    func handleEnter(forTask task: Todo) {
        guard let textField = textField(forText: task.what),
              let textView = textField.currentEditor() as? NSTextView,
              let position = textView.selectedRanges.first?.rangeValue.location
        else {
            return
        }
        switch position {
        case 0:
            let index: Int = task.index ?? list?.items.maxIndex() ?? 0
            list?.createNewTask(todo: newTaskText, at: index)
        case textView.textStorage?.length:
            handleMoveDown()
        default:
            list?.createNewTask(todo: newTaskText,
                                at: 1 + (task.index ?? list?.items.maxIndex() ?? 0))
        }
    }
    
    func handleMoveUp() {
        guard let index = focusedIndex() else {
            if focusedField == .newTask {
                guard let list = self.list,
                      !list.items.isEmpty else {
                    focusOnTopic()
                    return
                }
                focusedTaskDate = sortedPendingTasks.last?.created
            } else {
                focusOnNewTask()
            }
            return
        }
        if index > 0 {
            focusedTaskDate = sortedPendingTasks[index - 1].created
        } else {
            focusOnTopic()
        }
    }
    
    func handleMoveDown() {
        guard let index = focusedIndex() else {
            if focusedField == .topic {
                guard let list = self.list,
                      !list.items.isEmpty else {
                    focusOnNewTask()
                    return
                }
                focusedTaskDate = sortedPendingTasks.first?.created
            } else {
                focusOnTopic()
            }
            return
        }
        if index < sortedPendingTasks.endIndex - 1 {
            focusedTaskDate = sortedPendingTasks[index + 1].created
        } else {
            focusOnNewTask()
        }
    }
    
    func handleHover(_ isHover: Bool) {
        withAnimation {
            if isHover {
                isTopicHidden = false
            } else {
                updateTopicVisibility()
            }
        }
    }
    
    func handleDelete(isBackwards: Bool = false) -> Bool {
        guard let index = focusedIndex() else {
            return false
        }
        let task = sortedPendingTasks[index]
        if task.what.isEmpty {
            delete(task)
            var newIndex = index - (isBackwards ? 1 : 0)
            if newIndex < 0 {
                newIndex = sortedPendingTasks.endIndex - 1
            }
            focusedTaskDate = sortedPendingTasks[newIndex].created
            return true
        }
        return false
    }
    
    func handleDisappearance() {
        self.list?.delete()
    }
    
    func handleBringUp() {
        if let window = self.noteWindow,
           window.title.starts(with: "_"),
           let originalFrame = self.minimizedFromFrame
        {
            window.title = String(window.title.dropFirst())
            self.minimizedFromFrame = nil
            DispatchQueue.main.async {
                withAnimation {
                    window.setFrame(originalFrame, display: true, animate: true)
                } completion: {
                    withAnimation {
                        self.isMinimized = false
                    }
                }
            }
        }
    }
    
    func convertLegacyFontSizeSettingIfNeeded() {
        if fontSize < FontSize.xSmall.rawValue,
           let newFontSize = FontSize(fromLegacySetting: fontSize) {
            fontSize = newFontSize.rawValue
        }
    }
}

// MARK: Private methods

private extension Note {
    
    func delete(_ task: Todo) {
        modelContext.delete(task)
        do {
            try modelContext.save()
            list?.remove(task)
            updateWindowClosability()
        } catch {
            fatalError("Error on task deletion: \(error)")
        }
    }
    
    func updateWindowClosability() {
        guard let window = self.noteWindow,
              let closeButton = window.standardWindowButton(.closeButton),
              let list = self.list
        else {
            return
        }
        closeButton.isEnabled = list.isDeletable
    }
    
    func updateTopicVisibility() {
        let isComplete = list?.isComplete ?? false
        withAnimation {
            self.isTopicHidden = isTopicEmpty && (isComplete || focusedField != .topic)
        }
    }
    
    func focusOnTopic() {
        self.focusedTaskDate = nil
        self.focusedField = .topic
    }
    
    func focusOnNewTask() {
        self.focusedTaskDate = nil
        self.focusedField = .newTask
    }
    
    func focusedIndex() -> Int? {
        sortedPendingTasks.map({ $0.created }).firstIndex(of: focusedTaskDate)
    }
    
    func placeCursor(forText value: String) {
        placeCursor(forText: value, at: 0)
    }
    
    func placeCursor(forText value: String, at position: Int) {
        guard let textField = textField(forText: value) else {
            return
        }
        textField.currentEditor()?.selectedRange = NSMakeRange(position, position)
    }
    
    func textField(forText value: String) -> NSTextField? {
        guard let noteView = noteWindow?.contentView else {
            return nil
        }
        let textFields: [NSTextField] = noteView.getNestedSubviews<NSTextField>()
        for textField in textFields {
            if textField.stringValue == value {
                return textField
            }
        }
        return nil
    }
}

// MARK: Note components

private extension Note {
    
    @ViewBuilder
    func taskList(_ list: TodoList) -> some View {
        ZStack {
            Group {
                ScrollViewReader { scroll in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            listTopic()
                                .opacity(isTopScrolledOut || isTopicHidden ? 0 : 1)
                                .frame(height: isTopicHidden ? 1 : 30)
                                .padding(.bottom, CGFloat(fontSize - 10))
                            ForEach(sortedTasks, id: \.created) { item in
                                listItem(task: item)
                            }
                            if !list.isSystemList {
                                newListItem()
                                    .opacity(isDone || isTextBlurred ? 0 : 1)
                            } else {
                                systemContent(list)
                            }
                            Spacer()
                                .id(Id.bottomAnchor)
                        }
                        .onAppear {
                            if self.list!.topic == nil {
                                self.focusedField = .topic
                            } else {
                                self.focusedField = .newTask
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .minimizeAll)) { _ in
                            handleMinimize()
                        }
                    }
                    .modifier(ScrollFrame())
                    .onChange(of: list.items.count) {
                        withAnimation {
                            scroll.scrollTo(Id.bottomAnchor, anchor: .bottom)
                        }
                    }
                }
                if isTopScrolledOut {
                    scrollingHeader()
                }
            }
            .blur(radius: isTextBlurred ? 3 : 0)
            .opacity(windowAlpha / (isDone ? 2 : 1))
            if isDone {
                doneOverlay()
            }
        }
        .frame(minWidth: Layout.minNoteWidth,
               idealWidth: Layout.defaultNoteWidth,
               maxWidth: .infinity,
               minHeight: Layout.minNoteHeight,
               idealHeight: Layout.defaultNoteHeight,
               maxHeight: .infinity,
               alignment: .center)
        .background(WindowAccessor(note: Binding.constant(self), window: $noteWindow))
        .onAppear {
            handleKeyboard()
            self.isDone = list.isComplete
            self.wasAlreadyDone = list.isComplete
            convertLegacyFontSizeSettingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .visibility)) { notification in
            if let (toBlur, toNormal) = notification.object as? (Bool, Bool) {
                noteWindow?.level = toNormal ? .normal : .floating
                isTextBlurred = toBlur
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clean)) { notification in
            guard let listHash = notification.object as? String else {
                return
            }
            if list.hash == listHash {
                list.clean()
            }
        }
        .disabled(isTextBlurred)
    }
    
    @ViewBuilder
    func taskListProgess(_ list: TodoList) -> some View {
        let pendingCount: Int = list.items.filter({ !$0.isDone }).count
        let progressValue = list.items.isEmpty ? 0.0 : Float(list.items.count - pendingCount)
        let progressGoal = list.items.isEmpty ? 1 : list.items.count
        let progressComplete: Bool = pendingCount == 0 && !list.items.isEmpty
        let color: Color = progressComplete ? .accentColor : Color(nsColor: .checkboxBorder)
        let allDoneLabel = NSLocalizedString("all done", comment: "All tasks are completed")
        let pendingLabel = NSLocalizedString("pending", comment: "Tasks are pending")
        let emptyLabel = NSLocalizedString("no tasks", comment: "No tasks available")
        let label: String = progressComplete ? allDoneLabel : (list.items.isEmpty ? emptyLabel : pendingLabel)
        VStack {
            if (list.topic != nil) {
                Text(list.topic!)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, -32)
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Gauge(value: progressValue, in: 0...Float(progressGoal)) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(color)
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                    .padding(.leading, -19)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } currentValueLabel: {
                Text("\(pendingCount)")
                    .bold()
                    .font(.system(size: 30))
                    .foregroundStyle(color)
            }
            .gaugeStyle(.accessoryCircular)
            .padding(.top, list.topic != nil ? -18 : -25)
            .padding(.leading, 2)
            .tint(Gradient(colors: [.clear, color]))
        }
        .frame(minWidth: Layout.minimizedNoteWidth,
               idealWidth: Layout.minimizedNoteWidth,
               maxWidth: Layout.minimizedNoteWidth,
               minHeight: Layout.minimizedNoteHeight,
               idealHeight: Layout.minimizedNoteHeight,
               maxHeight: Layout.minimizedNoteHeight,
               alignment: .center)
        .background(WindowAccessor(note: Binding.constant(self), window: $noteWindow))
        .onTapGesture {
            handleBringUp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bringAllUp)) { _ in
            handleBringUp()
        }
    }
    
    @ViewBuilder
    func listTopic() -> some View {
        if let list = self.list {
            let listTaksOffset: CGFloat = 20 / CGFloat(FontSize.small.rawValue)
            let size = listTaksOffset * CGFloat(fontSize)
            GeometryReader { geometry in
                TextField("Topic",
                          text: Binding<String>(
                            get: { list.topic ?? "" },
                            set: { handleTopicEdit(to: $0) }
                          ))
                .textFieldStyle(PlainTextFieldStyle())
                .truncationMode(.tail)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .padding(.top, 5)
                .focused($focusedField, equals: .topic)
                .onChange(of: focusedField) {
                    if let topic = list.topic, focusedField == .topic {
                        placeCursor(forText: topic)
                    }
                    updateTopicVisibility()
                }
                .onChange(of: geometry.frame(in: .global)) {
                    let frame = geometry.frame(in: .global)
                    withAnimation(.easeInOut) {
                        self.isTopScrolledOut = frame.minY < 10
                    }
                }
                .onHover { isHover in
                    handleHover(isHover)
                }
                .onSubmit {
                    if list.items.isEmpty {
                        focusOnNewTask()
                    } else {
                        handleMoveDown()
                    }
                }
                .blur(radius: isTextBlurred ? 1 : 0)
            }
            .padding(.bottom, size)
        }
    }
    
    @ViewBuilder
    func headerListTopic() -> some View {
        if let topic = list?.topic {
            HStack {
                Text(topic)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(Color(.primaryFontColor))
                    .padding(.top, 2)
                    .padding(.leading, 70)
                    .padding(.trailing, 18)
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    func listItem(task: Todo) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Checkbox(checked: task.isDone)
                .disabled(task.what.isEmpty)
                .onToggle {
                    handleTaskToggle(task)
                    noteWindow?.makeFirstResponder(nil)
                }
                .padding(.vertical, 2)
            if task.isDone {
                Text(task.what)
                    .font(.system(size: CGFloat(fontSize)))
                    .foregroundColor(.accentColor)
                    .strikethrough(color: .accentColor)
            } else {
                TextField("New task.default",
                          text: Binding<String>(
                            get: { task.what },
                            set: { handleTaskEdit(task, to: $0) }
                          ),
                          axis: taskLineTruncation == .single ? .horizontal : .vertical)
                .disabled(list?.isSystemList ?? true)
                .if(taskLineTruncation == .single) { view in
                    view.truncationMode(.tail)
                }
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: CGFloat(fontSize)))
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .focused($focusedTaskDate, equals: task.created)
                .onChange(of: focusedTaskDate) {
                    if focusedTaskDate == task.created {
                        placeCursor(forText: task.what)
                    }
                }
                .onKeyPress(keys: [.return]) { _ in
                    handleEnter(forTask: task)
                    return .handled
                }
                .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                    guard focusedTaskDate == task.created else { return }
                    task.copy()
                }
                .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                    guard focusedTaskDate == task.created else { return }
                    task.paste()
                }
                .onSubmit {
                    handleMoveDown()
                }
            }
            Spacer()
        }
        .padding(.leading, 2)
        .if(task == sortedTasks.first) { view in
            view.onHover { isHover in
                handleHover(isHover)
            }
        }
    }
    
    @ViewBuilder
    func newListItem() -> some View {
        HStack(spacing: 8) {
            Checkbox()
                .disabled(true)
            TextField("New task", text: $newTaskText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: CGFloat(fontSize)))
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .onSubmit(handleNewTaskCommit)
                .focused($focusedField, equals: .newTask)
                .onChange(of: focusedField) {
                    if focusedField != .newTask && !newTaskText.isEmpty {
                        handleNewTaskCommit()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    handleNewTaskCommit()
                }
            Spacer()
        }
        .padding(.leading, 2)
        .padding(.bottom, 10)
        .if(sortedTasks.isEmpty) { view in
            view.onHover { isHover in
                handleHover(isHover)
            }
        }
    }
    
    @ViewBuilder
    func scrollingHeader() -> some View {
        VStack {
            ZStack {
                Rectangle()
                    .fill(Color(nsColor: self.color.withAlphaComponent(windowAlpha)))
                    .frame(width: .infinity, height: 30)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, x: 0, y: 1)
                headerListTopic()
            }
            Spacer()
        }
        .padding(.top, -30)
    }
    
    @ViewBuilder
    func doneOverlay() -> some View {
        VStack {
            Spacer()
            Image(systemName: "checkmark")
                .padding(.top, 12)
                .padding(.leading, 12)
                .font(.system(size: 90, weight: .bold))
                .foregroundColor(.accentColor)
                .symbolEffect(.bounce, value: isFadingAway)
            Text("Done!")
                .padding(.leading, 6)
                .padding(.bottom, wasAlreadyDone ? 60 : 30)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.accentColor)
            Spacer()
            if !wasAlreadyDone {
                ZStack {
                    ProgressView("Fading out...",
                                 value: fadeAwayProgress,
                                 total: Timeout.noteFadeOutSeconds)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .onReceive(timer) { _ in
                        if fadeAwayProgress < Timeout.noteFadeOutSeconds {
                            fadeAwayProgress += 0.05
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            self.isDone = false
                            fadeAwayProgress = 0.0
                        } label: {
                            Text("Cancel")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .opacity(windowAlpha * 0.9)
    }
    
    @ViewBuilder
    func systemContent(_ list: TodoList) -> some View {
        VStack {
            Spacer()
            if let content: String = list.systemContent {
                HStack {
                    Text(content)
                    Spacer()
                }
            }
            if let url = list.systemURL {
                Link("Visit release notes", destination: url)
                    .buttonStyle(BorderedProminentButtonStyle())
                    .padding()
                    .padding(.trailing, 15)
            }
        }
    }
}

// MARK: View modifiers

struct ScrollFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.top, 0)
            .padding(.trailing, 5)
            .padding(.leading, 20)
            .colorScheme(.light)
    }
}

// MARK: Note preview

#if DEBUG
#Preview {
    let configuration = ModelConfiguration(for: Todo.self, TodoList.self,
                                           isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Todo.self, TodoList.self,
                                        configurations: configuration)
    container.mainContext.insert(Todo.oneTask)
    container.mainContext.insert(Todo.anotherTask)
    container.mainContext.insert(Todo.undoneTask)
    container.mainContext.insert(TodoList.preview)
    return Note()
        .todoList(.preview)
        .modelContainer(container)
}
#endif
