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
    @AppStorage("notesOverviewLayout") private var layoutRawValue = NotesOverviewLayout.list.rawValue
    @State private var presentedNoteID: NoteID?
    @State private var noteToRename: Note?
    @State private var renamedTitle = ""
    @State private var noteToDelete: Note?
    @State private var deckOrder: [NoteID] = []
    @State private var currentDeckNoteID: NoteID?

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
                            currentIndex: currentDeckIndex,
                            summaries: appModel.taskSummaries,
                            taskPreviews: appModel.taskPreviews,
                            open: open,
                            rename: beginRename,
                            delete: { noteToDelete = $0 },
                            move: moveDeck
                        )
                    }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusMenu(status: appModel.syncStatus, syncNow: appModel.syncNow)
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
        Swift.Task {
            guard let note = try? await appModel.createNote() else { return }
            presentedNoteID = note.id
        }
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
                    Button("Delete", role: .destructive) { noteToDelete = note }
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

    private var currentDeckIndex: Int {
        guard let currentDeckNoteID,
              let index = deckOrder.firstIndex(of: currentDeckNoteID) else { return 0 }
        return index
    }

    private func open(_ note: Note) {
        presentedNoteID = note.id
    }

    private func reconcileDeckOrder() {
        let activeIDs = Set(activeNotes.map(\.id))
        let retainedIDs = deckOrder.filter(activeIDs.contains)
        let newIDs = activeNotes.map(\.id).filter { !retainedIDs.contains($0) }
        deckOrder = retainedIDs + newIDs
        if currentDeckNoteID.map(activeIDs.contains) != true {
            currentDeckNoteID = deckOrder.first
        }
    }

    private func moveDeck(_ direction: DeckNavigationDirection) {
        let currentIndex = currentDeckIndex
        let destination: Int
        switch direction {
        case .previous:
            destination = currentIndex - 1
        case .next:
            destination = currentIndex + 1
        }
        guard deckOrder.indices.contains(destination) else { return }
        currentDeckNoteID = deckOrder[destination]
    }
}

private enum NotesOverviewLayout: String, CaseIterable, Identifiable {
    case list
    case grid
    case deck

    var id: Self { self }

    var title: String {
        switch self {
        case .list: String(localized: "List")
        case .grid: String(localized: "Grid")
        case .deck: String(localized: "Deck")
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .deck: "rectangle.stack"
        }
    }
}

private enum DeckNavigationDirection {
    case previous
    case next
}

private enum NoteCardLayoutMetrics {
    private static let deckSizeMultiplier: CGFloat = 0.86

    static func gridHeight(in availableHeight: CGFloat) -> CGFloat {
        min(260, max(170, (availableHeight - 36) / 2.35))
    }

    static func deckHeight(in availableHeight: CGFloat) -> CGFloat {
        min(availableHeight * 0.60, 420) * deckSizeMultiplier
    }

    static func deckWidth(in availableWidth: CGFloat) -> CGFloat {
        min(availableWidth * 0.72, 320) * deckSizeMultiplier
    }
}

private struct NotesGridView: View {
    let notes: [Note]
    let summaries: [NoteID: NoteTaskSummary]
    let taskPreviews: [NoteID: [NoteTaskPreview]]
    let open: (Note) -> Void
    let rename: (Note) -> Void
    let delete: (Note) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = NoteCardLayoutMetrics.gridHeight(in: proxy.size.height)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(notes, id: \.id) { note in
                        NoteCard(
                            note: note,
                            summary: summaries[note.id],
                            tasks: taskPreviews[note.id] ?? [],
                            style: .grid,
                            height: cardHeight,
                            contentScale: 1,
                            rename: { rename(note) },
                            delete: { delete(note) }
                        )
                        .onTapGesture { open(note) }
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct NotesDeckView: View {
    let notes: [Note]
    let currentIndex: Int
    let summaries: [NoteID: NoteTaskSummary]
    let taskPreviews: [NoteID: [NoteTaskPreview]]
    let open: (Note) -> Void
    let rename: (Note) -> Void
    let delete: (Note) -> Void
    let move: (DeckNavigationDirection) -> Void
    @State private var transitionProgress: CGFloat = 0
    @State private var isCompletingSwipe = false

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = NoteCardLayoutMetrics.deckHeight(in: proxy.size.height)
            let gridCardHeight = NoteCardLayoutMetrics.gridHeight(in: proxy.size.height)
            let contentScale = cardHeight / gridCardHeight
            ZStack(alignment: .top) {
                ForEach(visibleCards) { item in
                    let isCurrentCard = item.relativePosition == 0
                    let effectivePosition = Double(item.relativePosition) - Double(transitionProgress)
                    let transform = cardTransform(at: effectivePosition)
                    NoteCard(
                        note: item.note,
                        summary: summaries[item.note.id],
                        tasks: taskPreviews[item.note.id] ?? [],
                        style: .deck,
                        height: cardHeight,
                        contentScale: contentScale,
                        rename: { rename(item.note) },
                        delete: { delete(item.note) }
                    )
                    .frame(
                        width: NoteCardLayoutMetrics.deckWidth(in: proxy.size.width)
                    )
                    .scaleEffect(transform.scale, anchor: .bottom)
                    .offset(x: transform.x, y: transform.y)
                    .rotationEffect(.degrees(transform.rotation), anchor: .bottom)
                    .opacity(transform.opacity)
                    .zIndex(100 - abs(effectivePosition))
                    .allowsHitTesting(isCurrentCard)
                    .onTapGesture {
                        if isCurrentCard { open(item.note) }
                    }
                }
            }
            .frame(width: proxy.size.width, height: max(0, proxy.size.height - 56), alignment: .top)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .contentShape(Rectangle())
            .gesture(swipeGesture(in: proxy.size))
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func swipeGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isCompletingSwipe else { return }
                transitionProgress = progress(for: value.translation.width, in: size.width)
            }
            .onEnded { value in
                guard !isCompletingSwipe else { return }
                let projectedProgress = progress(for: value.predictedEndTranslation.width, in: size.width)
                if canMoveNext,
                   transitionProgress > 0.48 || projectedProgress > 0.72 {
                    completeSwipe(.next, value: value, in: size)
                } else if canMovePrevious,
                          transitionProgress < -0.48 || projectedProgress < -0.72 {
                    completeSwipe(.previous, value: value, in: size)
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
                        transitionProgress = 0
                    }
                }
            }
    }

    private func completeSwipe(
        _ direction: DeckNavigationDirection,
        value: DragGesture.Value,
        in size: CGSize
    ) {
        isCompletingSwipe = true
        let projectedVelocity = min(4, abs(value.predictedEndTranslation.width - value.translation.width) / size.width)
        let destination: CGFloat = direction == .next ? 1 : -1

        withAnimation(
            .interpolatingSpring(stiffness: 180, damping: 22, initialVelocity: projectedVelocity),
            completionCriteria: .logicallyComplete
        ) {
            transitionProgress = destination
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                move(direction)
                transitionProgress = 0
                isCompletingSwipe = false
            }
        }
    }

    private var visibleCards: [DeckCardItem] {
        guard notes.indices.contains(currentIndex) else { return [] }
        let lowerBound = max(notes.startIndex, currentIndex - 3)
        let upperBound = min(notes.index(before: notes.endIndex), currentIndex + 3)
        return (lowerBound...upperBound).map { index in
            DeckCardItem(note: notes[index], relativePosition: index - currentIndex)
        }
    }

    private var canMovePrevious: Bool { currentIndex > notes.startIndex }
    private var canMoveNext: Bool { currentIndex + 1 < notes.endIndex }

    private func progress(for horizontalTranslation: CGFloat, in width: CGFloat) -> CGFloat {
        var progress = -horizontalTranslation / max(width * 0.36, 1)
        if progress > 0, !canMoveNext { progress *= 0.18 }
        if progress < 0, !canMovePrevious { progress *= 0.18 }
        return min(1.15, max(-1.15, progress))
    }

    private func cardTransform(at position: Double) -> DeckCardTransform {
        let direction = position.sign == .minus ? -1.0 : 1.0
        let magnitude = min(abs(position), 3)
        let horizontal = 44 * magnitude - 4 * magnitude * max(0, magnitude - 1)
        return DeckCardTransform(
            x: CGFloat(direction * horizontal),
            y: CGFloat(7 * magnitude + 1.5 * magnitude * magnitude),
            scale: CGFloat(1 - 0.038 * magnitude),
            rotation: direction * (3.2 * magnitude + 0.45 * magnitude * magnitude),
            opacity: max(0.46, 1 - 0.17 * magnitude)
        )
    }
}

private struct DeckCardItem: Identifiable {
    let note: Note
    let relativePosition: Int

    var id: NoteID { note.id }
}

private struct DeckCardTransform {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let rotation: Double
    let opacity: Double
}

private struct NoteCard: View {
    enum Style { case grid, deck }

    let note: Note
    let summary: NoteTaskSummary?
    let tasks: [NoteTaskPreview]
    let style: Style
    let height: CGFloat
    let contentScale: CGFloat
    let rename: () -> Void
    let delete: () -> Void
    @ScaledMetric(relativeTo: .headline) private var baseTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var baseChevronSize: CGFloat = 12

    private var title: String {
        guard let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return String(localized: "Untitled Note")
        }
        return title
    }

    var body: some View {
        let gaugeSize = 24 * contentScale * 0.8
        let cornerRadius = 16 * contentScale

        VStack(alignment: .leading, spacing: 12 * contentScale) {
            HStack(alignment: .center, spacing: 8 * contentScale) {
                Text(title)
                    .font(.system(size: baseTitleSize * contentScale, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 14 * contentScale) {
                    NoteCompletionGauge(summary: summary)
                        .foregroundStyle(.black)
                        .scaleEffect(gaugeSize / 40)
                        .frame(width: gaugeSize, height: gaugeSize)
                    Image(systemName: "chevron.right")
                        .font(.system(size: baseChevronSize * contentScale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .fixedSize()
            }

            NoteCardTaskList(tasks: tasks, style: style, contentScale: contentScale)
        }
        .padding(.horizontal, 14 * contentScale)
        .padding(.top, 14 * contentScale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(note.color.swiftUIColor)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.white.opacity(0.20))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 6 * contentScale, y: 3 * contentScale)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contextMenu {
            Button("Rename", action: rename)
            Button("Delete", role: .destructive, action: delete)
        }
        .accessibilityLabel(title)
        .accessibilityValue(summary?.accessibilityDescription ?? String(localized: "No tasks"))
        .accessibilityHint("Double tap to open the full checklist")
    }
}

private struct NoteCardTaskList: View {
    let tasks: [NoteTaskPreview]
    let style: NoteCard.Style
    let contentScale: CGFloat
    @ScaledMetric(relativeTo: .caption) private var baseTaskSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var baseCheckboxSize: CGFloat = 17

    var body: some View {
        Group {
            if tasks.isEmpty {
                Text("No tasks yet")
                    .font(.system(size: baseTaskSize * contentScale))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                LazyVStack(alignment: .leading, spacing: 8 * contentScale) {
                    ForEach(tasks) { task in
                        HStack(alignment: .top, spacing: 7 * contentScale) {
                            TaskCheckboxIndicator(
                                isChecked: task.isCompleted,
                                diameter: baseCheckboxSize * contentScale
                            )
                            Text(task.text)
                                .strikethrough(task.isCompleted)
                                .foregroundStyle(.black)
                                .lineLimit(style == .deck ? 2 : 1)
                        }
                        .font(.system(size: baseTaskSize * contentScale))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}
