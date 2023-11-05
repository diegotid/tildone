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
    @Query private var tasks: [Task]
    @State private var editedTask: String?
    @State private var editedTopic: String?

    private func handleTaskCommit() {
        guard let newStatement = self.editedTask else { return }
        let newTask = Task(order: self.tasks.count + 1, statement: newStatement)
        modelContext.insert(newTask)
        do {
            try modelContext.save()
            self.editedTask = nil
        } catch {
            fatalError("Error on task creation: \(error)")
        }
    }
    
    private func handleTaskEdit(_ task: Task, to statement: String) {
        task.statement = statement
        do {
            try modelContext.save()
        } catch {
            fatalError("Error on task edit: \(error)")
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                TextField(Copies.newTopicPlaceholder,
                          text: Binding<String>(
                            get: { self.editedTopic ?? "" },
                            set: { self.editedTopic = $0 }
                          )
                )
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Color(.primaryFontColor))
                .background(Color.clear)
                .padding(.top, 15)
                ForEach(tasks) { task in
                    HStack(spacing: 8) {
                        Checkbox()
                        TextField(Copies.newTaskPlaceholder,
                                  text: Binding<String>(
                                    get: { task.statement },
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
    Note().modelContainer(for: Task.self, inMemory: true)
}
