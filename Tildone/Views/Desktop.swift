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
    @State private var isMainWindowNew: Bool = false
    @State private var noteWindows: [NSWindow] = []
    @State private var mainWindow: NSWindow?
    @State private var foregroundWindow: NSWindow?
    @Binding var foregroundList: TodoList? {
        didSet { cleanUnfocusedNotes() }
    }
    
    @AppStorage("selectedArrangementCorner") var selectedArrangementCorner: ArrangementCorner = .bottomLeft
    @AppStorage("selectedArrangementAlignment") var selectedArrangementAlignment: ArrangementAlignment = .horizontal
    @AppStorage("selectedArrangementCornerMargin") var selectedArrangementCornerMargin: ArrangementSpacing = .medium
    @AppStorage("selectedArrangementSpacing") var selectedArrangementSpacing: ArrangementSpacing = .minimum
    
    static private var appWindowIds: [String] = [Id.aboutWindow, Id.updateWindow]

    var body: some View {
        noteWindow(for: lists.first)
            .background(WindowAccessor(window: $mainWindow)).onChange(of: mainWindow) {
                guard let list: TodoList = lists.first else { return }
                mainWindow?.setNoteStyle()
                mainWindow?.standardWindowButton(.closeButton)?.isHidden = !list.isDeletable
                mainWindow?.setFrameAutosaveName(ISO8601DateFormatter().string(from: list.created))
                mainWindow?.title = list.hash
                mainWindow?.titleVisibility = .hidden
                if let window = mainWindow {
                    noteWindows.append(window)
                }
                if isMainWindowNew {
                    let rect = NSRect(x: Layout.defaultNoteXPosition,
                                      y: Layout.defaultNoteYPosition,
                                      width: Layout.defaultNoteWidth,
                                      height: Layout.defaultNoteHeight)
                    mainWindow?.setFrame(rect, display: true)
                }
            }
            .onAppear {
                setWindowOptions()
                openNoteWindows()
                createWhatsNewNoteIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                deleteCompleteNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                arrangeNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arrange)) { _ in
                arrangeNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arrangeMinimized)) { _ in
                arrangeNotes(onlyMinimized: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .new)) { _ in
                createAndShowNewNote(at: foregroundWindowUpperRightCorner())
            }
            .onReceive(NotificationCenter.default.publisher(for: .close)) { _ in
                handleClose()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
                if let window = event.object as? NSWindow {
                    handleFocus(window)
                }
            }
    }
}

// MARK: Desktop event handlers

private extension Desktop {
    
    func openNoteWindows() {
        if lists.isEmpty {
            createNewNote()
            self.isMainWindowNew = true
        }
        for list in lists.dropFirst() {
            openWindow(for: list)
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
    
    func createAndShowNewNote(at position: CGPoint) {
        createNewNote()
        openWindow(for: lists.last!, position: position)
    }
    
    func handleFocus(_ window: NSWindow) {
        foregroundWindow = window
        if window.title == lists.first?.hash {
            foregroundList = lists.first
        } else if let windowId = window.identifier?.rawValue,
                  Desktop.appWindowIds.contains(windowId) {
            foregroundList = nil
        }
    }
    
    func handleClose() {
        if let list = foregroundList {
            if list.isDeletable {
                foregroundWindow?.close()
                noteWindows.removeAll(where: { $0.title == foregroundList?.hash })
            }
        } else {
            foregroundWindow?.close()
        }
    }
    
    func deleteCompleteNotes() {
        for list in lists.filter({ $0.isDeletable }) {
            list.delete()
        }
    }
    
    func arrangeNotes(onlyMinimized: Bool = false) {
        let horizontal: Bool = selectedArrangementAlignment == .horizontal
        let inverse: Bool = horizontal
            ? [.bottomRight, .topRight].contains(selectedArrangementCorner)
            : [.topLeft, .topRight].contains(selectedArrangementCorner)
        let sortedWindows = noteWindows
            .sorted(by: {
                switch (horizontal, inverse) {
                case (true, true): $0.frame.origin.x > $1.frame.origin.x
                case (true, false): $0.frame.origin.x < $1.frame.origin.x
                case (false, true): $0.frame.origin.y > $1.frame.origin.y
                case (false, false): $0.frame.origin.y < $1.frame.origin.y
                }
            })
            .filter {
                !onlyMinimized || $0.title.starts(with: "_")
            }
        positionOnScreen(sortedWindows)
    }
    
    func positionOnScreen(_ windows: [NSWindow], from: Int = 0) {
        guard let window: NSWindow = windows.first,
              let screenSize: CGSize = noteWindows.first?.screen?.frame.size else {
            return
        }
        let margin: Int = from > 0
            ? selectedArrangementSpacing.rawValue
            : selectedArrangementCornerMargin.rawValue
        let newPosition: Int = from + margin
        let windowX = Int(window.frame.width)
        let windowY = Int(window.frame.height)
        let horizontal: Bool = selectedArrangementAlignment == .horizontal
        let inverseX: Bool = [.bottomRight, .topRight].contains(selectedArrangementCorner)
        let inverseY: Bool = [.topLeft, .topRight].contains(selectedArrangementCorner)
        let newX: Int = horizontal ? newPosition : selectedArrangementCornerMargin.rawValue
        let newY: Int = !horizontal ? newPosition : selectedArrangementCornerMargin.rawValue
        let finalX: Int = inverseX ? Int(screenSize.width) - newX - windowX : newX
        let finalY: Int = inverseY ? Int(screenSize.height) - Frame.menuBarHeight - newY - windowY : newY
        let newFrame = NSRect(x: finalX, y: finalY, width: windowX, height: windowY)
        DispatchQueue.main.async {
            withAnimation {
                window.setFrame(newFrame, display: false, animate: true)
            }
        }
        let delta: Int = horizontal ? Int(window.frame.width) : Int(window.frame.height)
        let remainingWindows: [NSWindow] = Array(windows.dropFirst())
        
        positionOnScreen(remainingWindows, from: newPosition + delta)
    }
    
    func cleanUnfocusedNotes() {
        for list in lists {
            guard list != foregroundList else { continue }
            NotificationCenter.default.post(name: .clean, object: list.hash)
        }
    }
    
    func setWindowOptions() {
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        Task {
            let filterIntent = try await FocusFilter.current
            _ = try await filterIntent.perform()
        }
    }
    
    func createWhatsNewNoteIfNeeded() {
        Task {
            if let list: TodoList = await UpdateChecker.getNewReleaseCheckList() {
                createWhatsNewNote(checkList: list)
            }
        }
    }
    
    func createWhatsNewNote(checkList: TodoList) {
        modelContext.insert(checkList)
        do {
            try modelContext.save()
            DispatchQueue.main.async {
                openWindow(for: checkList)
            }
        } catch {
            debugPrint(error.localizedDescription)
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
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
                    if let window = event.object as? NSWindow {
                        foregroundWindow = window
                        if window.title == list?.hash {
                            foregroundList = existingList
                        } else if window.identifier?.rawValue == Id.aboutWindow {
                            foregroundList = nil
                        }
                    }
                }
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
        window.setNoteStyle(isSystem: list.isSystemList)
        window.standardWindowButton(.closeButton)?.isHidden = !list.isDeletable
        window.contentView = NSHostingView(rootView: noteWindow(for: list))
        window.setFrameAutosaveName(ISO8601DateFormatter().string(from: list.created))
        window.title = list.hash
        window.titleVisibility = .hidden
        noteWindows.append(window)
        if let origin = position {
            window.setFrameOrigin(
                NSPoint(x: origin.x - Layout.defaultNoteWidth / 2,
                        y: origin.y - Layout.defaultNoteHeight / 2)
            )
        }
        foregroundList = list
        foregroundWindow = window
    }
    
    func foregroundWindowUpperRightCorner() -> CGPoint {
        let window: NSWindow = foregroundWindow ?? mainWindow!
        return CGPoint(x: window.frame.maxX, y: window.frame.maxY)
    }
}
