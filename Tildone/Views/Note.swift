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
    var onAddNewNote: ((_ position: CGPoint) -> Void)?

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
    @FocusState private var focusedTaskCreation: Date?

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
            ZStack {
                Group {
                    ScrollViewReader { scroll in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                listTopic()
                                    .opacity(isTopScrolledOut || isTopicHidden ? 0 : 1)
                                    .frame(height: isTopicHidden ? 1 : 30)
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
                            .padding(.top, list.isDeletable && !list.isComplete ? 0 : -8)
                            .onAppear {
                                if self.list!.topic == nil {
                                    self.focusedField = .topic
                                } else {
                                    self.focusedField = .newTask
                                }
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
                    if let onAdd = onAddNewNote {
                        headerToolBar(onAdd: onAdd)
                    }
                }
                .blur(radius: isTextBlurred ? 3 : 0)
                .opacity(windowAlpha / (isDone ? 2 : 1))
                if isDone {
                    doneOverlay()
                }
            }
            .background(WindowAccessor(window: $noteWindow))
            .onAppear {
                handleKeyboard()
                self.isDone = list.isComplete
                self.wasAlreadyDone = list.isComplete
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
    }
}

// MARK: Note parameters

extension Note {
    
    func todoList(_ list: TodoList) -> Self {
        var modified: Note = self
        modified.list = list
        return modified
    }
    
    func onAddNewNote(_ action: @escaping (_ position: CGPoint) -> Void) -> Self {
        var modified: Note = self
        modified.onAddNewNote = action
        return modified
    }
}

// MARK: Note event handlers

private extension Note {
    
    func handleTaskCommit() {
        guard newTaskText.count > 0 else {
            return
        }
        list?.createNewTask(todo: newTaskText, at: list?.items.count ?? 0)
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
                && newTaskText.count > 0 {
                handleTaskCommit()
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
                focusedTaskCreation = sortedPendingTasks.last?.created
            } else {
                focusOnNewTask()
            }
            return
        }
        if index > 0 {
            focusedTaskCreation = sortedPendingTasks[index - 1].created
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
                focusedTaskCreation = sortedPendingTasks.first?.created
            } else {
                focusOnTopic()
            }
            return
        }
        if index < sortedPendingTasks.count - 1 {
            focusedTaskCreation = sortedPendingTasks[index + 1].created
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
        guard let index = focusedIndex(),
              index > 0,
              index < sortedPendingTasks.count - 1 else {
            return false
        }
        let task = sortedPendingTasks[index]
        if task.what.isEmpty {
            delete(task)
            let newIndex = index - (isBackwards ? 1 : 0)
            focusedTaskCreation = sortedPendingTasks[newIndex].created
            return true
        }
        return false
    }
    
    func handleDisappearance() {
        self.list?.delete()
    }
}

// MARK: Private methods

private extension Note {
    
    func delete(_ task: Todo) {
        modelContext.delete(task)
        do {
            try modelContext.save()
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
        closeButton.isHidden = !list.isDeletable
    }
    
    func updateTopicVisibility() {
        let isComplete = list?.isComplete ?? false
        withAnimation {
            self.isTopicHidden = isTopicEmpty && (isComplete || focusedField != .topic)
        }
    }
    
    func focusOnTopic() {
        self.focusedTaskCreation = nil
        self.focusedField = .topic
    }
    
    func focusOnNewTask() {
        self.focusedTaskCreation = nil
        self.focusedField = .newTask
    }
    
    func focusedIndex() -> Int? {
        sortedPendingTasks.map({ $0.created }).firstIndex(of: focusedTaskCreation)
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
    func listTopic() -> some View {
        if let list = self.list {
            GeometryReader { geometry in
                TextField("Topic",
                          text: Binding<String>(
                            get: { list.topic ?? "" },
                            set: { handleTopicEdit(to: $0) }
                          ))
                .textFieldStyle(PlainTextFieldStyle())
                .truncationMode(.tail)
                .font(.system(size: 20, weight: .bold, design: .rounded))
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
            .padding(.bottom, 20)
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
                    .padding(.leading, 21)
                    .padding(.trailing, 18)
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    func listItem(task: Todo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Checkbox(checked: task.isDone)
                .disabled(task.what.isEmpty)
                .onToggle {
                    handleTaskToggle(task)
                    noteWindow?.makeFirstResponder(nil)
                }
                .padding(.vertical, 2)
            if task.isDone {
                Text(task.what)
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
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .focused($focusedTaskCreation, equals: task.created)
                .onChange(of: focusedTaskCreation) {
                    if focusedTaskCreation == task.created {
                        placeCursor(forText: task.what)
                    }
                }
                .onKeyPress(keys: [.return]) { _ in
                    handleEnter(forTask: task)
                    return .handled
                }
                .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                    guard focusedTaskCreation == task.created else { return }
                    task.copy()
                }
                .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                    guard focusedTaskCreation == task.created else { return }
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
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .onSubmit(handleTaskCommit)
                .focused($focusedField, equals: .newTask)
                .onChange(of: focusedField) {
                    if focusedField != .newTask && !newTaskText.isEmpty {
                        handleTaskCommit()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    handleTaskCommit()
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
    func headerToolBar(onAdd: @escaping (_ position: CGPoint) -> Void) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    onAdd(NSEvent.mouseLocation)
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(Color(.primaryFontColor))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 6)
            }
            Spacer()
        }
        .padding(.top, -20)
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
                    if license == .pro {
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
            .frame(minWidth: Layout.minNoteWidth,
                   idealWidth: Layout.defaultNoteWidth,
                   maxWidth: .infinity,
                   minHeight: Layout.minNoteHeight,
                   idealHeight: Layout.defaultNoteHeight,
                   maxHeight: .infinity,
                   alignment: .center)
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
    container.mainContext.insert(TodoList.preview)
    return Note()
        .todoList(.preview)
        .modelContainer(container)
}
#endif
