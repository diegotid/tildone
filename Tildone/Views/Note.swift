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
    @Environment(\.modelContext) private var modelContext

    var list: TodoList?
    var onAddNewNote: ((_ position: CGPoint) -> Void)?

    @State private var editedTask: String = ""
    @State private var editedListTopic: String = ""
    @State private var isTopScrolledOut: Bool = false
    @FocusState private var isNewTaskFocused: Bool

    var body: some View {
        if let list = self.list {
            ZStack {
                ScrollViewReader { scroll in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            listTopic()
                                .opacity(isTopScrolledOut ? 0 : 1)
                            ForEach(list.items.sorted(by: { $0.order < $1.order })) { item in
                                listItem(task: item)
                            }
                            newListItem()
                            Spacer()
                                .id("bottom")
                        }
                        .onAppear {
                            self.isNewTaskFocused = self.list!.topic != nil
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
                    VStack {
                        ZStack {
                            noteHeader()
                            headerListTopic()
                        }
                        Spacer()
                    }
                    .padding(.top, -30)
                }
                if let onAdd = onAddNewNote {
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
    
    func handleTaskCommit() {
        guard let list = self.list else {
            return
        }
        let newTask = Todo(editedTask, order: list.items.count + 1)
        newTask.list = self.list
        modelContext.insert(newTask)
        self.editedTask = ""
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task creation: \(error)")
        }
    }
    
    func handleTaskEdit(_ task: Todo, to what: String) {
        task.what = what
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task edit: \(error)")
        }
    }
    
    func handleTaskToggle(_ task: Todo) {
        task.done.toggle()
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task edit: \(error)")
        }
    }
    
    func handleTopicEdit(to topic: String) {
        guard let _ = self.list else {
            return
        }
        self.list!.topic = topic
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on topic edit: \(error)")
        }
    }
}

// MARK: Note components

private extension Note {
    
    @ViewBuilder
    func listTopic() -> some View {
        if let list = self.list {
            GeometryReader { geometry in
                TextField(Copies.listTopicPlaceholder,
                          text: Binding<String>(
                            get: { list.topic ?? "" },
                            set: { handleTopicEdit(to: $0) }
                          ))
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .padding(.top, 5)
                .focused($isNewTaskFocused, equals: false)
                .onSubmit {
                    self.isNewTaskFocused = true
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
            Checkbox(checked: task.done)
                .onToggle {
                    handleTaskToggle(task)
                }
            if task.done {
                Text(task.what)
                    .foregroundColor(Color(.checkboxOnFill))
                    .strikethrough(color: Color(.checkboxOnFill))
            } else {
                TextField(Copies.newTaskPlaceholder,
                          text: Binding<String>(
                            get: { task.what },
                            set: { handleTaskEdit(task, to: $0) }
                          ))
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
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
            TextField(Copies.newTaskPlaceholder, text: $editedTask)
                .onSubmit(handleTaskCommit)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .focused($isNewTaskFocused)
            Spacer()
        }
        .padding(.leading, 2)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    func noteHeader() -> some View {
        Rectangle()
            .fill(Color(nsColor: .noteBackground))
            .frame(width: .infinity, height: 30)
            .shadow(color: .black.opacity(0.2), radius: 1.5, x: 0, y: 1)
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

#Preview {
    Note()
        .todoList(.preview)
        .modelContainer(for: [Todo.self, TodoList.self], inMemory: true)
}
