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
    @State private var isPresentingNewNote = false
    @State private var noteToRename: Note?
    @State private var renamedTitle = ""
    @State private var noteToDelete: Note?
    @State private var deckOrder: [NoteID] = []
    @State private var showsAbout = false
    @State private var showsWelcome = false
    @State private var searchText = ""
    @State private var departingNote: Note?
    @State private var isDepartingNoteFading = false
    @State private var departureTask: Swift.Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var overviewNotes: [Note] {
        guard let departingNote,
              appModel.taskSummaries[departingNote.id]?.isComplete == true,
              !activeNotes.contains(where: { $0.id == departingNote.id }) else { return activeNotes }
        return [departingNote] + activeNotes
    }

    private var displayedNotes: [Note] {
        guard !searchText.isEmpty else { return overviewNotes }
        return overviewNotes.filter { note in
            note.title?.matchesSearch(searchText) == true
                || appModel.taskListTexts[note.id]?.matchesSearch(searchText) == true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if overviewNotes.isEmpty && appModel.isCheckingCloudForNotes {
                    ContentUnavailableView {
                        ProgressView()
                    } description: {
                        Text("Loading Notes…")
                    }
                } else if overviewNotes.isEmpty && !appModel.isEmptyStateConfirmed {
                    UnconfirmedEmptyWorkspaceStatus(appModel: appModel)
                } else if overviewNotes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes Yet", systemImage: "checklist")
                    } description: {
                        Text("Create a note to keep a small checklist close at hand.")
                    } actions: {
                        Button("Create Note", action: createNote)
                    }
                } else if displayedNotes.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    switch layout {
                    case .list:
                        notesList
                    case .grid:
                        NotesGridView(
                            notes: displayedNotes,
                            departingNoteID: departingNote?.id,
                            isDepartingNoteFading: isDepartingNoteFading,
                            summaries: appModel.taskSummaries,
                            taskPreviews: appModel.taskPreviews,
                            open: open,
                            rename: beginRename,
                            delete: { noteToDelete = $0 }
                        )
                    case .deck:
                        NotesDeckView(
                            notes: orderedDeckNotes,
                            departingNoteID: departingNote?.id,
                            isDepartingNoteFading: isDepartingNoteFading,
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
            .searchable(text: $searchText, prompt: "Search Notes and Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    TildoneiOSSyncStatusMenu(
                        appModel: appModel,
                        showsLaunchProgress: appModel.isCheckingCloudForNotes && !activeNotes.isEmpty,
                        showAbout: { showsAbout = true },
                        showWelcome: { showsWelcome = true }
                    )
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
                        .disabled(!appModel.hasWorkspace)
                }
            }
            .navigationDestination(item: $presentedNoteID) { noteID in
                ChecklistView(
                    appModel: appModel,
                    noteID: noteID,
                    isCreatingNote: isPresentingNewNote,
                    onCompletionStarted: beginDeparture,
                    onCompletionExited: finishDeparture
                )
            }
            .navigationDestination(isPresented: $showsAbout) {
                TildoneiOSAboutView()
            }
        }
        .sheet(isPresented: $showsWelcome, onDismiss: { WelcomeOnboarding.finish() }) {
            WelcomeOnboardingView { showsWelcome = false }
        }
        .onAppear { reconcileDeckOrder() }
        .onChange(of: overviewNotes.map(\.id)) { _, _ in
            reconcileDeckOrder()
        }
        .onChange(of: departingNote.flatMap { appModel.taskSummaries[$0.id]?.isComplete }) { _, isComplete in
            guard departingNote != nil, isComplete != true else { return }
            departureTask?.cancel()
            departingNote = nil
            isDepartingNoteFading = false
        }
        .alert("Use iCloud for Tildone?", isPresented: Binding(
            get: { appModel.shouldOfferCloudAdoption },
            set: { if !$0 { appModel.dismissCloudAdoptionOffer() } }
        )) {
            Button("Keep on This iPhone", role: .cancel) {
                appModel.keepNotesOnThisIPhone()
            }
            Button("Use iCloud") {
                appModel.useICloudAndCombineNotes()
            }
        } message: {
            Text("Tildone can combine the notes on this iPhone with your private iCloud notes. The originals will remain on this iPhone.")
        }
        .overlay {
            if appModel.isWorkspaceTransitionInProgress {
                ProgressView("Copying Notes to iCloud…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .alert("Couldn’t Use iCloud", isPresented: Binding(
            get: { appModel.workspaceTransitionFailed },
            set: { if !$0 { appModel.dismissWorkspaceTransitionError() } }
        )) {
            Button("OK") { appModel.dismissWorkspaceTransitionError() }
        } message: {
            Text("Your notes are still safe on this iPhone. Please try again later.")
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
        isPresentingNewNote = true
        presentedNoteID = appModel.createNoteAndPresent()
    }

    private func beginRename(_ note: Note) {
        noteToRename = note
        renamedTitle = note.title ?? ""
    }

    private var notesList: some View {
        List {
            ForEach(displayedNotes, id: \.id) { note in
                NavigationLink {
                    ChecklistView(
                        appModel: appModel,
                        noteID: note.id,
                        onCompletionStarted: beginDeparture,
                        onCompletionExited: finishDeparture
                    )
                } label: {
                    NoteListRow(
                        note: note,
                        summary: appModel.taskSummaries[note.id],
                        taskListText: appModel.taskListTexts[note.id],
                        taskPreview: appModel.taskPreviews[note.id]?.first
                    )
                }
                .opacity(note.id == departingNote?.id && isDepartingNoteFading ? 0 : 1)
                .disabled(note.id == departingNote?.id)
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
        deckOrder.compactMap { noteID in displayedNotes.first(where: { $0.id == noteID }) }
    }

    private func open(_ note: Note) {
        isPresentingNewNote = false
        presentedNoteID = note.id
    }

    private func reconcileDeckOrder() {
        let existingIDs = Set(appModel.notes.map(\.id))
        let retainedIDs = deckOrder.filter(existingIDs.contains)
        let newIDs = overviewNotes.map(\.id).filter { !retainedIDs.contains($0) }
        deckOrder = retainedIDs + newIDs
    }

    private func beginDeparture(_ noteID: NoteID) {
        departureTask?.cancel()
        guard let note = appModel.notes.first(where: { $0.id == noteID }) else { return }
        departingNote = note
        isDepartingNoteFading = false
        reconcileDeckOrder()
    }

    private func finishDeparture(_ noteID: NoteID) {
        guard departingNote?.id == noteID else { return }
        departureTask?.cancel()
        departureTask = Swift.Task {
            try? await Swift.Task.sleep(for: .milliseconds(reduceMotion ? 100 : 350))
            guard !Swift.Task.isCancelled,
                  departingNote?.id == noteID else { return }
            if reduceMotion || UIAccessibility.isVoiceOverRunning {
                departingNote = nil
                return
            }
            withAnimation(.easeOut(duration: 0.55)) {
                isDepartingNoteFading = true
            }
            try? await Swift.Task.sleep(for: .milliseconds(550))
            guard !Swift.Task.isCancelled,
                  departingNote?.id == noteID else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                departingNote = nil
                isDepartingNoteFading = false
            }
        }
    }
}

private extension String {
    func matchesSearch(_ query: String) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

private struct UnconfirmedEmptyWorkspaceStatus: View {
    let appModel: TildoneiOSApplicationModel
    @ObservedObject private var syncPresentation: TildoneiOSSyncPresentation

    init(appModel: TildoneiOSApplicationModel) {
        self.appModel = appModel
        _syncPresentation = ObservedObject(wrappedValue: appModel.syncPresentation)
    }

    var body: some View {
        WorkspaceStatusView(status: syncPresentation.status) {
            appModel.syncNow()
        }
    }
}
