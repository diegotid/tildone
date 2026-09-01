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
    static let gaugeScale: CGFloat = 0.5
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

private struct TildoneiOSSyncStatusMenu: View {
    let appModel: TildoneiOSApplicationModel
    @ObservedObject private var presentation: TildoneiOSSyncPresentation

    init(appModel: TildoneiOSApplicationModel) {
        self.appModel = appModel
        _presentation = ObservedObject(wrappedValue: appModel.syncPresentation)
    }

    var body: some View {
        SyncStatusMenu(
            status: presentation.status,
            transportState: presentation.transportState,
            canControlTransport: appModel.canControlTransport,
            syncNow: appModel.syncNow,
            pause: appModel.pauseTransport,
            resume: appModel.resumeTransport
        )
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
            let gridCardHeight = NoteCardLayoutMetrics.gridHeight(in: proxy.size.height)
            let contentScale = cardHeight / gridCardHeight
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(notes, id: \.id) { note in
                        NoteCard(
                            note: note,
                            summary: summaries[note.id],
                            tasks: taskPreviews[note.id] ?? [],
                            style: .grid,
                            height: cardHeight,
                            contentScale: contentScale,
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
    let summaries: [NoteID: NoteTaskSummary]
    let taskPreviews: [NoteID: [NoteTaskPreview]]
    let open: (Note) -> Void
    let rename: (Note) -> Void
    let delete: (Note) -> Void

    private var carouselGroups: [DeckCarouselGroup] {
        let notesByColor = Dictionary(grouping: notes, by: \.color)
        var groups = NoteColor.allCases.compactMap { color -> DeckCarouselGroup? in
            guard let colorNotes = notesByColor[color], colorNotes.count > 1 else { return nil }
            return DeckCarouselGroup(id: .color(color), notes: colorNotes)
        }

        let singletonNotes = notes.filter { notesByColor[$0.color]?.count == 1 }
        if !singletonNotes.isEmpty {
            groups.append(DeckCarouselGroup(id: .singleNoteColors, notes: singletonNotes))
        }
        return groups
    }

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = NoteCardLayoutMetrics.deckHeight(in: proxy.size.height)
            let gridCardHeight = NoteCardLayoutMetrics.gridHeight(in: proxy.size.height)
            let contentScale = cardHeight / gridCardHeight

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(carouselGroups) { group in
                        DeckCarousel(
                            notes: group.notes,
                            summaries: summaries,
                            taskPreviews: taskPreviews,
                            cardHeight: cardHeight,
                            contentScale: contentScale,
                            open: open,
                            rename: rename,
                            delete: delete
                        )
                    }
                }
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

}

private struct DeckCarouselGroup: Identifiable {
    enum ID: Hashable {
        case color(NoteColor)
        case singleNoteColors
    }

    let id: ID
    let notes: [Note]
}

private struct DeckCarousel: View {
    let notes: [Note]
    let summaries: [NoteID: NoteTaskSummary]
    let taskPreviews: [NoteID: [NoteTaskPreview]]
    let cardHeight: CGFloat
    let contentScale: CGFloat
    let open: (Note) -> Void
    let rename: (Note) -> Void
    let delete: (Note) -> Void
    @State private var currentNoteID: NoteID?
    @State private var transitionProgress: CGFloat = 0
    @State private var isCompletingSwipe = false

    var body: some View {
        GeometryReader { proxy in
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
                    .frame(width: NoteCardLayoutMetrics.deckWidth(in: proxy.size.width))
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
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .background {
                DeckHorizontalPanRecognizer(
                    canMove: canMove,
                    changed: { translation, _ in handlePanChanged(translation, in: proxy.size) },
                    ended: { translation, velocity in
                        handlePanEnded(translation, velocity: velocity, in: proxy.size)
                    },
                    cancelled: cancelPan
                )
            }
        }
        .frame(height: cardHeight + 52)
        .onAppear(perform: reconcileCurrentNote)
        .onChange(of: notes.map(\.id)) { _, _ in reconcileCurrentNote() }
    }

    private func handlePanChanged(_ translation: CGFloat, in size: CGSize) {
        guard !isCompletingSwipe else { return }
        transitionProgress = progress(for: translation, in: size.width)
    }

    private func handlePanEnded(_ translation: CGFloat, velocity: CGFloat, in size: CGSize) {
        guard !isCompletingSwipe else { return }
        let projectedProgress = progress(for: translation + velocity * 0.18, in: size.width)
        if canMoveNext,
           transitionProgress > 0.48 || projectedProgress > 0.72 {
            completeSwipe(.next, velocity: velocity, in: size)
        } else if canMovePrevious,
                  transitionProgress < -0.48 || projectedProgress < -0.72 {
            completeSwipe(.previous, velocity: velocity, in: size)
        } else {
            cancelPan()
        }
    }

    private func cancelPan() {
        withAnimation(.interpolatingSpring(stiffness: 280, damping: 28)) {
            transitionProgress = 0
        }
    }

    private func completeSwipe(
        _ direction: DeckNavigationDirection,
        velocity: CGFloat,
        in size: CGSize
    ) {
        isCompletingSwipe = true
        let projectedVelocity = min(4, abs(velocity) / max(size.width, 1))
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
                currentNoteID = notes[destinationIndex(for: direction)].id
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

    private var currentIndex: Int {
        guard let currentNoteID,
              let index = notes.firstIndex(where: { $0.id == currentNoteID }) else { return 0 }
        return index
    }

    private var canMovePrevious: Bool { currentIndex > notes.startIndex }
    private var canMoveNext: Bool { currentIndex + 1 < notes.endIndex }

    private func canMove(_ direction: DeckNavigationDirection) -> Bool {
        switch direction {
        case .previous: canMovePrevious
        case .next: canMoveNext
        }
    }

    private func destinationIndex(for direction: DeckNavigationDirection) -> Int {
        switch direction {
        case .previous: currentIndex - 1
        case .next: currentIndex + 1
        }
    }

    private func reconcileCurrentNote() {
        let activeIDs = Set(notes.map(\.id))
        if currentNoteID.map(activeIDs.contains) != true {
            currentNoteID = notes.first?.id
        }
    }

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

private struct DeckHorizontalPanRecognizer: UIViewRepresentable {
    let canMove: (DeckNavigationDirection) -> Bool
    let changed: (CGFloat, CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void
    let cancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(canMove: canMove, changed: changed, ended: ended, cancelled: cancelled)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.attach(to: view) }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.canMove = canMove
        context.coordinator.changed = changed
        context.coordinator.ended = ended
        context.coordinator.cancelled = cancelled
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canMove: (DeckNavigationDirection) -> Bool
        var changed: (CGFloat, CGFloat) -> Void
        var ended: (CGFloat, CGFloat) -> Void
        var cancelled: () -> Void
        private let panGesture: UIPanGestureRecognizer
        private weak var trackingView: UIView?
        private weak var scrollView: UIScrollView?

        init(
            canMove: @escaping (DeckNavigationDirection) -> Bool,
            changed: @escaping (CGFloat, CGFloat) -> Void,
            ended: @escaping (CGFloat, CGFloat) -> Void,
            cancelled: @escaping () -> Void
        ) {
            self.canMove = canMove
            self.changed = changed
            self.ended = ended
            self.cancelled = cancelled
            panGesture = UIPanGestureRecognizer()
            super.init()
            panGesture.addTarget(self, action: #selector(handlePan))
            panGesture.delegate = self
            panGesture.cancelsTouchesInView = false
        }

        func attach(to view: UIView) {
            trackingView = view
            guard scrollView == nil, let enclosingScrollView = enclosingScrollView(from: view) else { return }
            enclosingScrollView.addGestureRecognizer(panGesture)
            enclosingScrollView.panGestureRecognizer.require(toFail: panGesture)
            scrollView = enclosingScrollView
        }

        func detach() {
            panGesture.view?.removeGestureRecognizer(panGesture)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = panGesture.velocity(in: scrollView)
            guard abs(velocity.x) > abs(velocity.y) * 1.35 else { return false }
            return canMove(velocity.x < 0 ? .next : .previous)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let trackingView, let scrollView else { return false }
            let carouselFrame = trackingView.convert(trackingView.bounds, to: scrollView)
            return carouselFrame.contains(touch.location(in: scrollView))
        }

        @objc private func handlePan() {
            let translation = panGesture.translation(in: scrollView)
            let velocity = panGesture.velocity(in: scrollView)
            switch panGesture.state {
            case .began, .changed:
                changed(translation.x, velocity.x)
            case .ended:
                ended(translation.x, velocity.x)
            case .cancelled, .failed:
                cancelled()
            default:
                break
            }
        }
    }
}

private func enclosingScrollView(from view: UIView) -> UIScrollView? {
    var candidate = view.superview
    while let current = candidate {
        if let scrollView = current as? UIScrollView { return scrollView }
        candidate = current.superview
    }
    var responder: UIResponder? = view.next
    while let current = responder {
        if let scrollView = current as? UIScrollView { return scrollView }
        responder = current.next
    }
    return nil
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
                    NoteCompletionGauge(summary: summary, labelColor: .black)
                        .foregroundStyle(.black)
                        .scaleEffect(gaugeSize / 30)
                        .frame(width: gaugeSize, height: gaugeSize)
                    Image(systemName: "chevron.right")
                        .font(.system(size: baseChevronSize * contentScale, weight: .semibold))
                        .foregroundStyle(.black)
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
                            if let subtaskProgress = task.subtaskProgress {
                                TaskSubtaskProgressGauge(
                                    progress: subtaskProgress,
                                    size: baseCheckboxSize * contentScale * NoteListMetrics.gaugeScale
                                )
                            } else {
                                TaskCheckboxIndicator(
                                    isChecked: task.isCompleted,
                                    diameter: baseCheckboxSize * contentScale * NoteListMetrics.checboxScale
                                )
                            }
                            Text(task.text)
                                .strikethrough(task.isCompleted || task.subtaskProgress?.fraction == 1)
                                .foregroundStyle(.black)
                                .lineLimit(style == .deck ? 2 : 1)
                        }
                        .font(.system(size: baseTaskSize * contentScale))
                        .padding(.leading, 1 + CGFloat(task.indentLevel) * baseCheckboxSize * contentScale)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}
