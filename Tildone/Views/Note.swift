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
    @FocusState private var isNewTaskFocused: Bool
    
    init(_ list: TodoList) {
        self.list = list
        self.editedListTopic = list.topic ?? ""
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                listTopic()
                ForEach(list.items.sorted(by: { $0.order < $1.order })) { item in
                    listItem(task: item)
                }
                newListItem()
                Spacer()
            }
            .onAppear {
                self.isNewTaskFocused = self.list.topic != nil
            }
        }
        .padding(.top, 0)
        .padding(.trailing, 5)
        .padding(.leading, 20)
        .padding(.bottom, 20)
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
    }
    
    @ViewBuilder
    func listItem(task: Todo) -> some View {
        HStack(spacing: 8) {
            Checkbox()
            TextField(Copies.newTaskPlaceholder,
                      text: Binding<String>(
                        get: { task.what },
                        set: { handleTaskEdit(task, to: $0) }
                      ))
            .textFieldStyle(PlainTextFieldStyle())
            .foregroundColor(Color(.primaryFontColor))
            .background(Color.clear)
            Spacer()
        }.padding(.leading, 2)
    }
    
    @ViewBuilder
    func newListItem() -> some View {
        HStack(spacing: 8) {
            Checkbox()
            TextField(Copies.newTaskPlaceholder, text: $editedTask)
                .onSubmit(handleTaskCommit)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .focused($isNewTaskFocused)
            Spacer()
        }.padding(.leading, 2)
    }
}

#Preview {
    Note(.preview).modelContainer(for: Todo.self, inMemory: true)
}
