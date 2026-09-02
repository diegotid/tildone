//
//  NotesListView.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import UIKit
import TildoneDomain

enum NoteListMetrics {
    static let checboxScale: CGFloat = 0.7
    static let gaugeScale: CGFloat = 0.6
}

struct NotesListView: View {
    let appModel: TildoneiOSApplicationModel
    @ObservedObject private var overviewPresentation: TildoneiOSOverviewPresentation
    @AppStorage("notesOverviewLayout") private var layoutRawValue = NotesOverviewLayout.list.rawValue
    @State private var presentedNoteID: NoteID?
    @State private var noteToRename: Note?
    @State private var renamedTitle = ""
    @State private var noteToDelete: Note?
    @State private var deckOrder: [NoteID] = []

    init(appModel: TildoneiOSApplicationModel) {
        self.appModel = appModel
        _overviewPresentation = ObservedObject(wrappedValue: appModel.overviewPresentation)
    }

    private var layout: NotesOverviewLayout {
        get { NotesOverviewLayout(rawValue: layoutRawValue) ?? .list }
        nonmutating set { layoutRawValue = newValue.rawValue }
    }

    private var activeNotes: [Note] {
        appModel.notes.filter { note in
            appModel.taskSummaries[note.id]?.isComplete != true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeNotes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes Yet", systemImage: "checklist")
                    } description: {
                        Text("Create a note to keep a small checklist close at hand.")
                    } actions: {
                        Button("Create Note", action: createNote)
                    }
                } else {
                    switch layout {
                    case .list:
                        notesList
                    case .grid:
                        NotesGridView(
                            notes: activeNotes,
                            summaries: appModel.taskSummaries,
                            taskPreviews: appModel.taskPreviews,
                            open: open,
                            rename: beginRename,
                            delete: { noteToDelete = $0 }
                        )
                    case .deck:
                        NotesDeckView(
                            notes: orderedDeckNotes,
                            summaries: appModel.taskSummaries,
                            taskPreviews: appModel.taskPreviews,
                            open: open,
                            rename: beginRename,
                            delete: { noteToDelete = $0 }
                        )
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    TildoneiOSSyncStatusMenu(appModel: appModel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Layout", selection: Binding(
                            get: { layout }, set: { layout = $0 }
                        )) {
                            ForEach(NotesOverviewLayout.allCases) { layout in
                                Label(layout.title, systemImage: layout.systemImage)
                                    .tag(layout)
                            }
                        }
                    } label: {
                        Label("Choose layout", systemImage: layout.systemImage)
                    }
                    .accessibilityLabel("Choose notes layout")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TildoneiOSUndoMenuButton(
                        presentation: appModel.undoPresentation
                    ) {
                        try await appModel.undoLatestAction()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createNote) { Label("New Note", systemImage: "plus") }
                        .accessibilityLabel("Create note")
                }
            }
            .navigationDestination(item: $presentedNoteID) { noteID in
                ChecklistView(appModel: appModel, noteID: noteID)
            }
        }
        .onAppear { reconcileDeckOrder() }
        .onChange(of: activeNotes.map(\.id)) { _, _ in reconcileDeckOrder() }
        .alert("Rename Note", isPresented: Binding(
            get: { noteToRename != nil }, set: { if !$0 { noteToRename = nil } }
        )) {
            TextField("Title", text: $renamedTitle)
            Button("Cancel", role: .cancel) { noteToRename = nil }
            Button("Save") {
                guard let note = noteToRename else { return }
                Swift.Task { try? await appModel.rename(noteID: note.id, title: renamedTitle) }
                noteToRename = nil
            }
        }
        .confirmationDialog("Delete this note?", isPresented: Binding(
            get: { noteToDelete != nil }, set: { if !$0 { noteToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                guard let note = noteToDelete else { return }
                Swift.Task { try? await appModel.delete(noteID: note.id) }
                noteToDelete = nil
            }
        } message: { Text("Its checklist will be removed from your active notes.") }
    }

    private func createNote() {
        presentedNoteID = appModel.createNoteAndPresent()
    }

    private func beginRename(_ note: Note) {
        noteToRename = note
        renamedTitle = note.title ?? ""
    }

    private var notesList: some View {
        List {
            ForEach(activeNotes, id: \.id) { note in
                NavigationLink {
                    ChecklistView(appModel: appModel, noteID: note.id)
                } label: {
                    NoteListRow(
                        note: note,
                        summary: appModel.taskSummaries[note.id],
                        taskListText: appModel.taskListTexts[note.id]
                    )
                }
                .contextMenu { noteActions(for: note) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if let summary = appModel.taskSummaries[note.id],
                       summary.isComplete || summary.isEmpty {
                        Button("Delete", role: .destructive) { noteToDelete = note }
                    }
                    Button("Rename") { beginRename(note) }.tint(.orange)
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func noteActions(for note: Note) -> some View {
        Menu("Note color") {
            ForEach(NoteColor.allCases) { color in
                Button {
                    Swift.Task { try? await appModel.setColor(noteID: note.id, color: color) }
                } label: {
                    if note.color == color {
                        Label(color.localizedLabel, systemImage: "checkmark")
                    } else {
                        Text(color.localizedLabel)
                    }
                }
            }
        }
        Button("Rename") { beginRename(note) }
        Button("Delete", role: .destructive) { noteToDelete = note }
    }

    private var orderedDeckNotes: [Note] {
        deckOrder.compactMap { noteID in activeNotes.first(where: { $0.id == noteID }) }
    }

    private func open(_ note: Note) {
        presentedNoteID = note.id
    }

    private func reconcileDeckOrder() {
        let activeIDs = Set(activeNotes.map(\.id))
        let retainedIDs = deckOrder.filter(activeIDs.contains)
        let newIDs = activeNotes.map(\.id).filter { !retainedIDs.contains($0) }
        deckOrder = retainedIDs + newIDs
    }
}
