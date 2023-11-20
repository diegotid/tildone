//
//  Desktop.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import SwiftData

// MARK: Desktop view

struct Desktop: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lists: [TodoList]
    @State private var mainWindow: NSWindow?
    @State private var lastWindow: NSWindow?
    
    var body: some View {
        noteWindow(for: lists.first)
            .background(WindowAccessor(window: $mainWindow)).onChange(of: mainWindow) {
                guard let list: TodoList = lists.first else { return }
                mainWindow?.setNoteStyle()
                mainWindow?.standardWindowButton(.closeButton)?.isHidden = !list.isComplete
                mainWindow?.setFrameAutosaveName(ISO8601DateFormatter().string(from: list.created))
            }
            .onAppear {
                if lists.isEmpty {
                    createNewNote()
                }
                for list in lists.dropFirst() {
                    openWindow(for: list)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                deleteCompleteNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .new)) { _ in
                createAndShowNewNote(at: lastWindowUpperRightCorner())
            }
    }
}

// MARK: Desktop event handlers

private extension Desktop {
   
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
    
    func createAndShowNewNote(at position: CGPoint) {
        createNewNote()
        openWindow(for: lists.last!, position: position)
    }
    
    func deleteCompleteNotes() {
        for list in lists.filter({ $0.isComplete && $0.topic == nil }) {
            delete(list)
        }
    }
}

// MARK: Desktop components

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
}
 
// MARK: Window functions

private extension Desktop {
    
    func openWindow(for list: TodoList, position: CGPoint? = nil) {
        let windowLayout = NSRect(x: 0,
                                  y: 0,
                                  width: Layout.defaultNoteWidth,
                                  height: Layout.defaultNoteHeight)
        let window = NSWindow(contentRect: windowLayout,
                              styleMask: [.titled, .closable, .resizable, .borderless],
                              backing: .buffered,
                              defer: false)
        window.setNoteStyle()
        window.standardWindowButton(.closeButton)?.isHidden = !list.isComplete
        window.contentView = NSHostingView(rootView: noteWindow(for: list))
        window.setFrameAutosaveName(ISO8601DateFormatter().string(from: list.created))
        if let origin = position {
            window.setFrameOrigin(
                NSPoint(x: origin.x - Layout.defaultNoteWidth / 2,
                        y: origin.y - Layout.defaultNoteHeight / 2)
            )
        }
        self.lastWindow = window
    }
    
    func lastWindowUpperRightCorner() -> CGPoint {
        let window: NSWindow = lastWindow ?? mainWindow!
        return CGPoint(x: window.frame.maxX, y: window.frame.maxY)
    }
}
