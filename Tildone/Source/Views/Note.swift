//
//  Note.swift
//  Tildone
//
//  Created by Diego on 24/4/21.
//

import SwiftUI

struct Note: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext

    @FetchRequest(
        entity: Task.entity(),
        sortDescriptors: []
    ) var tasks: FetchedResults<Task>

//    @State private var tasks: [Task] = []
    
    @State private var editedTask = ""
    @State private var editedTopic = ""
    
    func handleTaskCommit() {
        
        let newTask = Task(context: managedObjectContext)
        newTask.done = false
        newTask.statement = editedTask
        do {
            try managedObjectContext.save()
        } catch {
            let errorMessage = error as NSError
            fatalError("Error on task creation: \(errorMessage)")
        }
    }

    var body: some View {
        
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                TextField(Copies.newTopicPlaceholder,text: $editedTopic)
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
                                    get: { task.statement! },
                                    set: { print(" > \($0)") }
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
                                get: { self.editedTask },
                                set: { self.editedTask = $0 }
                              )
                    ) { isEditing in
                        print("isEditing")
                    } onCommit: {
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

struct Note_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
