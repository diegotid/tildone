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
    @State private var editedTask: String?
    @State private var editedListTitle: String?
    
    init(_ list: TodoList) {
        self.list = list
    }

    private func handleTaskCommit() {
        guard let task = self.editedTask else {
            return
        }
        let newTask = Todo(task, order: self.list.items.count + 1)
        modelContext.insert(newTask)
        do {
            try modelContext.save()
            self.editedTask = nil
        } catch {
            fatalError("Error on task creation: \(error)")
        }
    }
    
    private func handleTaskEdit(_ todo: Todo, to what: String) {
        todo.what = what
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task edit: \(error)")
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                TextField(Copies.newListTitlePlaceholder,
                          text: Binding<String>(
                            get: { self.editedListTitle ?? "" },
                            set: { self.editedListTitle = $0 }
                          )
                )
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .padding(.top, 15)
                ForEach(list.items) { task in
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
                HStack(spacing: 8) {
                    Checkbox()
                    TextField(Copies.newTaskPlaceholder,
                              text: Binding<String>(
                                get: { self.editedTask ?? "" },
                                set: { self.editedTask = $0 }
                              )
                    ) { _ in } onCommit: {
                        handleTaskCommit()
                    }
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(Color(.primaryFontColor))
                    .background(Color.clear)
                    Spacer()
                }.padding(.leading, 2)
                Spacer()
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

#Preview {
    Note(.preview).modelContainer(for: Todo.self, inMemory: true)
}
