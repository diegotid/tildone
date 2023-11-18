//
//  Desktop.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import SwiftData

struct Desktop: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lists: [TodoList]
    @State private var window: NSWindow?
    
    var body: some View {
        noteWindow(for: lists.first)
            .background(WindowAccessor(window: $window)).onChange(of: window) {
                window?.setNoteStyle()
                window?.standardWindowButton(.closeButton)?.isHidden = true
            }
            .onAppear {
                if lists.isEmpty {
                    createNewNote()
                }
                for list in lists.dropFirst() {
                    if list.isEmpty {
                        delete(list)
                    } else {
                        openWindow(for: list)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .new)) { _ in
                createAndShowNewNote()
            }
    }
}

private extension Desktop {
    
    @ViewBuilder
    func noteWindow(for list: TodoList?) -> some View {
        if let existingList = list {
            Note()
                .todoList(existingList)
                .onAddNewNote(createAndShowNewNote)
                .environment(\.modelContext, modelContext)
                .frame(minWidth: Layout.minNoteWidth,
                       idealWidth: Layout.defaultNoteWidth,
                       maxWidth: .infinity,
                       minHeight: Layout.minNoteHeight,
                       idealHeight: Layout.defaultNoteHeight,
                       maxHeight: .infinity,
                       alignment: .center)
        }
    }
    
    func createNewNote() {
        let newList = TodoList()
        modelContext.insert(newList)
        do {
            try modelContext.save()
        } catch {
            fatalError("Could not create a first list: \(error)")
        }
    }
    
    func delete(_ list: TodoList) {
        modelContext.delete(list)
        do {
            try modelContext.save()
        } catch {
            fatalError("Could not delete list: \(error)")
        }
    }
    
    func createAndShowNewNote() {
        createNewNote()
        openWindow(for: lists.last!)
    }
    
    func openWindow(for list: TodoList) {
        let windowLayout = NSRect(x: 0,
                                  y: 0,
                                  width: Layout.defaultNoteWidth,
                                  height: Layout.defaultNoteHeight)
        let window = NSWindow(contentRect: windowLayout,
                              styleMask: [.titled, .closable, .resizable, .borderless],
                              backing: .buffered,
                              defer: false)
        window.setNoteStyle()
        window.standardWindowButton(.closeButton)?.isHidden = !list.isEmpty
        window.contentView = NSHostingView(rootView: noteWindow(for: list))
        window.setFrameAutosaveName(ISO8601DateFormatter().string(from: list.created))
    }
}
