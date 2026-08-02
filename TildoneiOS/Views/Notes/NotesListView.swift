//
//  NotesListView.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneDomain

struct NotesListView: View {
    @ObservedObject var appModel: TildoneiOSApplicationModel
    @State private var createdNoteID: NoteID?
    @State private var noteToRename: Note?
    @State private var renamedTitle = ""
    @State private var noteToDelete: Note?

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
                            .contextMenu {
                                Button("Rename") { beginRename(note) }
                                Button("Delete", role: .destructive) { noteToDelete = note }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { noteToDelete = note }
                                Button("Rename") { beginRename(note) }.tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusMenu(status: appModel.syncStatus, syncNow: appModel.syncNow)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createNote) { Label("New Note", systemImage: "plus") }
                        .accessibilityLabel("Create note")
                }
            }
            .navigationDestination(item: $createdNoteID) { noteID in
                ChecklistView(appModel: appModel, noteID: noteID)
            }
        }
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
        Swift.Task {
            guard let note = try? await appModel.createNote() else { return }
            createdNoteID = note.id
        }
    }

    private func beginRename(_ note: Note) {
        noteToRename = note
        renamedTitle = note.title ?? ""
    }
}
