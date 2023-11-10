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
    
    var body: some View {
        note(for: lists.first)
            .onAppear {
                if lists.isEmpty {
                    createFirst()
                }
                for list in lists.dropFirst() {
                    openWindow(for: list)
                }
            }
    }
}

private extension Desktop {
    
    @ViewBuilder func note(for list: TodoList?) -> some View {
        if (list == nil) {
            EmptyView()
        } else {
            Note(list!)
                .background(Color(nsColor: .noteBackground))
                .frame(minWidth: Layout.minNoteWidth,
                       idealWidth: Layout.defaultNoteWidth,
                       maxWidth: .infinity,
                       minHeight: Layout.minNoteHeight,
                       idealHeight: Layout.defaultNoteHeight,
                       maxHeight: .infinity,
                       alignment: .center)
        }
    }
    
    func createFirst() {
        let newList = TodoList()
        modelContext.insert(newList)
        do {
            try modelContext.save()
        } catch {
            fatalError("Could not create a first list: \(error)")
        }
    }
    
    func openWindow(for list: TodoList) {
        let windowLayout = NSRect(x: 0,
                                  y: 0,
                                  width: Layout.defaultNoteWidth,
                                  height: Layout.defaultNoteHeight)
        let window = NSWindow(contentRect: windowLayout,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless],
                          backing: .buffered,
                          defer: false)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.backgroundColor = .noteBackground
        window.contentView = NSHostingView(rootView: note(for: list))
        window.setFrameAutosaveName(ISO8601DateFormatter().string(from: list.created))
   }
}
