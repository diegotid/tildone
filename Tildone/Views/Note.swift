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

    var list: TodoList?
    var sortedTasks: [Todo] {
        (list?.items ?? [])
            .sorted(by: { $0.created < $1.created })
    }
    var sortedPendingTasks: [Todo] {
        (list?.items ?? [])
            .filter({ $0.done == nil })
            .sorted(by: { $0.created < $1.created })
    }
    var onAddNewNote: ((_ position: CGPoint) -> Void)?

    @State private var noteWindow: NSWindow?
    @State private var editedTask: String = ""
    @State private var isTopScrolledOut: Bool = false
    @FocusState private var isTopicFocused: Bool
    @FocusState private var isNewTaskFocused: Bool
    @FocusState private var focusedTaskCreation: Date?

    private var timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    @State private var isAlreadyDone: Bool = false
    @State private var isDone: Bool = false {
        didSet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if !isAlreadyDone {
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
                noteWindow?.backgroundColor = .noteBackground.withAlphaComponent(windowAlpha)
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
                                    .opacity(isTopScrolledOut || isDone && (list.topic ?? "").isEmpty ? 0 : 1)
                                ForEach(sortedTasks, id: \.created) { item in
                                    listItem(task: item)
                                }
                                newListItem()
                                    .opacity(isDone ? 0 : 1)
                                Spacer()
                                    .id("bottom")
                            }
                            .onAppear {
                                self.isTopicFocused = self.list!.topic == nil
                                self.isNewTaskFocused = !self.isTopicFocused
                            }
                        }
                        .modifier(ScrollFrame())
                        .onChange(of: list.items.count) {
                            withAnimation {
                                scroll.scrollTo("bottom", anchor: .bottom)
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
                .opacity(windowAlpha / (isDone ? 2 : 1))
                if isDone {
                    doneOverlay()
                }
            }
            .background(WindowAccessor(window: $noteWindow))
            .onAppear {
                handleKeyboard()
                self.isDone = list.isComplete
                self.isAlreadyDone = list.isComplete
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
    
    func onAddNewNote(_ action: @escaping (_ position: CGPoint) -> Void) -> Self {
        var modified: Note = self
        modified.onAddNewNote = action
        return modified
    }
}

// MARK: Note event handlers

private extension Note {
    
    func delete(_ task: Todo) {
        modelContext.delete(task)
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task deletion: \(error)")
        }
    }
    
    func handleTaskCommit() {
        guard editedTask.count > 0 else {
            return
        }
        let newTask = Todo(editedTask.capitalizingFirstLetter())
        newTask.list = self.list
        modelContext.insert(newTask)
        self.editedTask = ""
        updateWindowClosability()
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task creation: \(error)")
        }
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
        list.topic = topic.capitalizingFirstLetter()
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on topic edit: \(error)")
        }
    }
    
    func handleKeyboard() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
            if event.keyCode == Keyboard.tabKey
                && isNewTaskFocused == true
                && editedTask.count > 0 {
                handleTaskCommit()
                return nil
            } else if event.keyCode == Keyboard.arrowUp {
                handleMoveUp()
                return nil
            } else if event.keyCode == Keyboard.arrowDown {
                handleMoveDown()
                return nil
            } else {
                return event
            }
        }
    }
    
    func handleMoveUp() {
        guard let focusIndex = sortedPendingTasks.map({ $0.created }).firstIndex(of: focusedTaskCreation) else {
            if isNewTaskFocused {
                focusedTaskCreation = sortedPendingTasks.last?.created
            } else {
                focusedTaskCreation = nil
                isNewTaskFocused = true
                isTopicFocused = false
            }
            return
        }
        if focusIndex > 0 {
            focusedTaskCreation = sortedPendingTasks[focusIndex - 1].created
        } else {
            focusedTaskCreation = nil
            isNewTaskFocused = false
            isTopicFocused = true
        }
    }
    
    func handleMoveDown() {
        guard let focusIndex = sortedPendingTasks.map({ $0.created }).firstIndex(of: focusedTaskCreation) else {
            if isTopicFocused {
                focusedTaskCreation = sortedPendingTasks.first?.created
            } else {
                focusedTaskCreation = nil
                isNewTaskFocused = false
                isTopicFocused = true
            }
            return
        }
        if focusIndex < sortedPendingTasks.count - 1 {
            focusedTaskCreation = sortedPendingTasks[focusIndex + 1].created
        } else {
            focusedTaskCreation = nil
            isNewTaskFocused = true
            isTopicFocused = false
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
    
    func handleDisappearance() {
        guard let list = self.list else {
            return
        }
        modelContext.delete(list)
        do {
            try modelContext.save()
        } catch {
            fatalError("Could not delete list: \(error)")
        }
    }
    
    func placeCursor(forText value: String) {
        guard let noteView = noteWindow?.contentView else { return }
        let textFields: [NSTextField] = noteView.getNestedSubviews<NSTextField>()
        for textField in textFields {
            if textField.stringValue == value {
                textField.currentEditor()?.selectedRange = NSMakeRange(0, 0)
            }
        }
    }
}

// MARK: Note components

private extension Note {
    
    @ViewBuilder
    func listTopic() -> some View {
        if let list = self.list {
            GeometryReader { geometry in
                TextField(Copy.listTopicPlaceholder,
                          text: Binding<String>(
                            get: { list.topic ?? "" },
                            set: { handleTopicEdit(to: $0) }
                          ))
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .padding(.top, 5)
                .focused($isTopicFocused)
                .onChange(of: isTopicFocused) {
                    if let topic = list.topic, isTopicFocused {
                        placeCursor(forText: topic)
                    }
                }
                .onSubmit {
                    handleMoveDown()
                }
                .onChange(of: geometry.frame(in: .global)) {
                    let frame = geometry.frame(in: .global)
                    withAnimation(.easeInOut) {
                        self.isTopScrolledOut = frame.minY < 15
                    }
                }
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
        HStack(spacing: 8) {
            Checkbox(checked: task.isDone)
                .onToggle {
                    handleTaskToggle(task)
                    noteWindow?.makeFirstResponder(nil)
                }
            if task.isDone {
                Text(task.what)
                    .foregroundColor(.accentColor)
                    .strikethrough(color: .accentColor)
            } else {
                TextField(Copy.newTaskPlaceholder,
                          text: Binding<String>(
                            get: { task.what },
                            set: { handleTaskEdit(task, to: $0) }
                          ))
                .textFieldStyle(PlainTextFieldStyle())
                .truncationMode(.tail)
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .focused($focusedTaskCreation, equals: task.created)
                .onChange(of: focusedTaskCreation) {
                    if focusedTaskCreation == task.created {
                        placeCursor(forText: task.what)
                    }
                }
                .onKeyPress(Keyboard.backspaceKey) {
                    if task.what.count > 0 {
                        return .ignored
                    } else {
                        delete(task)
                        return .handled
                    }
                }
            }
            Spacer()
        }
        .padding(.leading, 2)
    }
    
    @ViewBuilder
    func newListItem() -> some View {
        HStack(spacing: 8) {
            Checkbox()
                .disabled(true)
            TextField(Copy.newTaskPlaceholder, text: $editedTask)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .onSubmit(handleTaskCommit)
                .focused($isNewTaskFocused)
                .onChange(of: isNewTaskFocused) {
                    if !editedTask.isEmpty {
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
    }
    
    @ViewBuilder
    func scrollingHeader() -> some View {
        VStack {
            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .noteBackground.withAlphaComponent(windowAlpha)))
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
                .padding(.bottom, isAlreadyDone ? 60 : 30)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.accentColor)
            Spacer()
            if !isAlreadyDone {
                ZStack {
                    ProgressView(Copy.noteFadingOutDisplay,
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
                                Text(Copy.cancel)
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
