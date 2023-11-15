//
//  Note.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import SwiftData

struct Note: View {
    @Environment(\.modelContext) private var modelContext
    @State private var list: TodoList
    @State private var editedTask: String = ""
    @State private var editedListTopic: String = ""
    @State private var isTopScrolledOut: Bool = false
    @FocusState private var isNewTaskFocused: Bool
    
    var onAddNewNote: () -> Void
    
    init(_ list: TodoList, onAdd: @escaping () -> Void) {
        self.list = list
        self.editedListTopic = list.topic ?? ""
        self.onAddNewNote = onAdd
    }

    var body: some View {
        ZStack {
            ScrollViewReader { scroll in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        listTopic()
                        ForEach(list.items.sorted(by: { $0.order < $1.order })) { item in
                            listItem(task: item)
                        }
                        newListItem()
                        Spacer()
                            .id("bottom")
                    }
                    .onAppear {
                        self.isNewTaskFocused = self.list.topic != nil
                    }
                }
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
                .onChange(of: list.items.count) {
                    withAnimation {
                        scroll.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            if isTopScrolledOut {
                withAnimation {
                    VStack {
                        Rectangle()
                            .fill(Color(nsColor: .noteBackground))
                            .frame(width: .infinity, height: 30)
                            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        Spacer()
                    }
                    .padding(.top, -30)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button(action: onAddNewNote) {
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

extension Note {
    
    func handleTaskCommit() {
        let newTask = Todo(editedTask, order: self.list.items.count + 1)
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
        self.list.topic = topic
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on topic edit: \(error)")
        }
    }
    
    @ViewBuilder
    func listTopic() -> some View {
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
                self.isTopScrolledOut = frame.minY < 15
            }
        }
        .padding(.bottom, 20)
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
}

#Preview {
    Note(.preview, onAdd: {})
        .modelContainer(for: [Todo.self, TodoList.self], inMemory: true)
}
