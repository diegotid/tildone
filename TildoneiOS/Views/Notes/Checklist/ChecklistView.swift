//
//  ChecklistView.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync
import UIKit

struct ChecklistView: View {
    let appModel: TildoneiOSApplicationModel
    @ObservedObject private var presentation: TildoneiOSNotePresentation
    let noteID: NoteID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    @State private var newTaskText = ""
    @State private var title = ""
    @State private var titleBaseline: String?
    @State private var keepsTitleInputVisible = false
    @State private var collapsedTaskIDs: Set<TaskID> = []
    @State private var taskInsertionTargetID: TaskID?
    @State private var taskInsertionText = ""
    @State private var pendingTaskInsertionID: TaskID?
    @State private var showsInsertionHint = false
    @FocusState private var focusedTask: TaskID?
    @FocusState private var isAddingTask: Bool
    @FocusState private var isAddingTaskAbove: Bool
    @FocusState private var isEditingTitle: Bool

    init(appModel: TildoneiOSApplicationModel, noteID: NoteID) {
        self.appModel = appModel
        self.noteID = noteID
        _presentation = ObservedObject(wrappedValue: appModel.presentation(for: noteID))
    }

    private var note: Note? { presentation.snapshot.note }
    private var tasks: [Task] { presentation.snapshot.tasks }

    private var isInEditMode: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var isUntitled: Bool {
        note?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private var canEditTasks: Bool {
        Self.normalizedTitle(title) != nil || !tasks.isEmpty
    }

    private var showsTitleInput: Bool {
        isInEditMode || isEditingTitle || isUntitled || keepsTitleInputVisible
    }

    private var usesInlineNavigationTitle: Bool {
        showsTitleInput
    }

    var body: some View {
        Group {
            if let note {
                let subtaskProgresses = TaskHierarchy.subtaskProgresses(in: tasks)
                ScrollViewReader { scrollProxy in
                List {
                    if showsTitleInput {
                        TextField("Note title", text: $title)
                            .focused($isEditingTitle)
                            .font(.title2.weight(.semibold))
                            .submitLabel(.done)
                            .onSubmit { saveTitle() }
                            .onChange(of: isEditingTitle) { wasEditing, isEditing in
                                guard wasEditing, !isEditing else { return }
                                finishTitleEditing()
                            }
                    }

                    Section {
                        ForEach(visibleTasks) { visibleTask in
                            let index = visibleTask.index
                            let task = visibleTask.task
                            let hasSubtasks = TaskHierarchy.hasSubtasks(at: index, in: tasks)
                            let canIndent = index > 0
                                && tasks[index - 1].indentLevel >= task.indentLevel
                            let canOutdent = task.indentLevel > 0
                            if taskInsertionTargetID == task.id {
                                taskInsertionRow(above: task)
                                    .id("task-insertion-\(task.id)")
                            }
                            TaskRow(
                                task: task,
                                subtaskProgress: subtaskProgresses[task.id],
                                subtasksExpanded: hasSubtasks
                                    ? !collapsedTaskIDs.contains(task.id)
                                    : nil,
                                canIndent: canIndent,
                                canOutdent: canOutdent,
                                focusedTask: $focusedTask,
                                onCommit: { value in
                                    try? await appModel.edit(taskID: task.id, text: value)
                                },
                                onToggle: {
                                    try? await appModel.setCompletion(taskID: task.id, completed: !task.isCompleted)
                                },
                                onToggleSubtasks: {
                                    toggleSubtasks(at: index)
                                },
                                onIndent: {
                                    await changeIndentation(taskID: task.id, outdent: false)
                                },
                                onOutdent: {
                                    await changeIndentation(taskID: task.id, outdent: true)
                                },
                                onMoveUp: {
                                    await move(taskID: task.id, by: -1)
                                },
                                onMoveDown: {
                                    await move(taskID: task.id, by: 1)
                                }
                            )
                            .id(task.id)
                            .deleteDisabled(!task.isCompleted)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if canIndent {
                                    Button {
                                        Swift.Task {
                                            await changeIndentation(taskID: task.id, outdent: false)
                                        }
                                    } label: {
                                        swipeActionLabel("Make subtask", systemImage: "arrow.turn.down.right")
                                    }
                                    .tint(.indigo)
                                    .accessibilityLabel("Make subtask")
                                }
                                if canOutdent {
                                    Button {
                                        Swift.Task {
                                            await changeIndentation(taskID: task.id, outdent: true)
                                        }
                                    } label: {
                                        swipeActionLabel("Promote task", systemImage: "arrow.turn.left.up")
                                    }
                                    .tint(.blue)
                                    .accessibilityLabel("Promote task")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                if task.isCompleted {
                                    Button(role: .destructive) {
                                        deleteTask(task.id)
                                    } label: {
                                        swipeActionLabel("Delete", systemImage: "trash")
                                    }
                                }
                                Button {
                                    beginAddingTask(above: task.id)
                                } label: {
                                    swipeActionLabel("Add above", systemImage: "plus")
                                }
                                .tint(.green)
                                .accessibilityLabel("Add above")
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                                dimensions[.leading] + CGFloat(task.indentLevel) * 24
                            }
                        }
                        .onDelete(perform: deleteTasks)
                        .onMove(perform: move)

                        if !isInEditMode && (taskInsertionTargetID == nil || !taskInsertionText.isEmpty) {
                            TextField("New task", text: $newTaskText)
                                .focused($isAddingTask)
                                .submitLabel(.next)
                                .onSubmit { addTask() }
                                .accessibilityLabel("New task")
                                .frame(minHeight: 33, maxHeight: 33)
                                .id(Self.newTaskSlotID)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                    } footer: {
                        if showsInsertionHint {
                            Text("To insert anywhere, swipe a task and tap Add above.")
                        }
                    }
                }
                .navigationTitle(usesInlineNavigationTitle ? "" : note.title!)
                .navigationBarTitleDisplayMode(usesInlineNavigationTitle ? .inline : .large)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if canEditTasks && !isInEditMode {
                            Button {
                                addTaskFromHeader(scrollProxy: scrollProxy)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("Add task")
                        }
                        if canEditTasks {
                            Button {
                                withAnimation {
                                    editMode?.wrappedValue = isInEditMode ? .inactive : .active
                                }
                            } label: {
                                Image(systemName: isInEditMode ? "checkmark" : "pencil")
                            }
                            .accessibilityLabel(isInEditMode ? "Done" : "Edit")
                        }
                    }

                    if !isInEditMode {
                        if #available(iOS 26.0, *) {
                            ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                TildoneiOSUndoMenuButton(
                                    presentation: appModel.undoPresentation
                                ) {
                                    try await appModel.undoLatestAction()
                                }
                                Divider()
                                Picker("Note color", selection: Binding(
                                    get: { note.color },
                                    set: { color in
                                        Swift.Task {
                                            try? await appModel.setColor(noteID: noteID, color: color)
                                        }
                                    }
                                )) {
                                    ForEach(NoteColor.allCases) { color in
                                        Label {
                                            Text(color.localizedLabel)
                                        } icon: {
                                            Image(uiImage: NoteColorMenuSwatch.image(for: color))
                                                .renderingMode(.original)
                                        }
                                        .tag(color)
                                    }
                                }
                            } label: {
                                NoteColorPickerSymbol(color: note.color)
                            }
                            .accessibilityLabel("Note color")
                        }
                    }
                }
                .onDisappear {
                    saveTitle()
                    saveNewTaskIfNeeded()
                    saveTaskAboveIfNeeded()
                }
                }
            } else {
                ContentUnavailableView("This note was deleted", systemImage: "trash")
            }
        }
        .task {
            synchronizeWithPresentation()
            keepsTitleInputVisible = isUntitled
            isEditingTitle = isUntitled
            isAddingTask = !isUntitled && tasks.isEmpty
        }
        .onChange(of: presentation.snapshot) { oldSnapshot, newSnapshot in
            if oldSnapshot.note != nil, newSnapshot.note == nil { dismiss() }
            else { synchronizeWithPresentation() }
        }
        .onChange(of: newTaskText) { _, text in
            if !text.isEmpty {
                showsInsertionHint = false
            }
        }
    }

    private func synchronizeWithPresentation() {
        guard note != nil else { return }
        let parentIDs = Set(tasks.indices.compactMap { index in
            TaskHierarchy.hasSubtasks(at: index, in: tasks) ? tasks[index].id : nil
        })
        collapsedTaskIDs.formIntersection(parentIDs)
        if !isEditingTitle || titleBaseline == nil {
            title = note?.title ?? ""
            titleBaseline = Self.normalizedTitle(note?.title)
        }
    }

    private func saveTitle() {
        let normalized = Self.normalizedTitle(title)
        guard normalized != titleBaseline else { return }
        titleBaseline = normalized
        Swift.Task {
            try? await appModel.rename(noteID: noteID, title: normalized)
        }
    }

    private func finishTitleEditing() {
        if Self.normalizedTitle(title) == titleBaseline {
            title = note?.title ?? ""
            titleBaseline = Self.normalizedTitle(note?.title)
        } else {
            saveTitle()
        }
        if keepsTitleInputVisible, Self.normalizedTitle(title) != nil {
            isAddingTask = true
        }
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    private func addTask() {
        let text = newTaskText
        newTaskText = ""
        Swift.Task {
            _ = try? await appModel.addTask(noteID: noteID, text: text, after: tasks)
            isAddingTask = true
        }
    }

    private func addTaskFromHeader(scrollProxy: ScrollViewProxy) {
        showsInsertionHint = newTaskText.isEmpty
        focusedTask = nil
        withAnimation {
            scrollProxy.scrollTo(Self.newTaskSlotID, anchor: .bottom)
        }
        isAddingTask = true
    }

    private func saveNewTaskIfNeeded() {
        let text = newTaskText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        newTaskText = ""
        Swift.Task {
            _ = try? await appModel.addTask(noteID: noteID, text: text, after: tasks)
        }
    }

    private func beginAddingTask(above taskID: TaskID) {
        saveTaskAboveIfNeeded()
        focusedTask = nil
        taskInsertionText = ""
        pendingTaskInsertionID = taskID
        Swift.Task {
            try? await Swift.Task.sleep(nanoseconds: 800_000_000)
            guard pendingTaskInsertionID == taskID else { return }
            taskInsertionTargetID = taskID
            await Swift.Task.yield()
            guard pendingTaskInsertionID == taskID,
                  taskInsertionTargetID == taskID else { return }
            isAddingTaskAbove = true
        }
    }

    private func cancelAddingTaskAbove() {
        pendingTaskInsertionID = nil
        isAddingTaskAbove = false
        taskInsertionTargetID = nil
        taskInsertionText = ""
    }

    private func saveTaskAboveIfNeeded() {
        guard taskInsertionTargetID != nil else { return }
        guard !taskInsertionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelAddingTaskAbove()
            return
        }
        addTaskAbove()
    }

    private func addTaskAbove() {
        guard let targetTaskID = taskInsertionTargetID else { return }
        let text = taskInsertionText
        cancelAddingTaskAbove()
        Swift.Task {
            _ = try? await appModel.addTask(
                noteID: noteID,
                text: text,
                before: targetTaskID
            )
        }
    }

    private func taskInsertionRow(above task: TildoneDomain.Task) -> some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: 32, height: 33)
            TextField("New task", text: $taskInsertionText)
                .focused($isAddingTaskAbove)
                .submitLabel(.done)
                .onSubmit(addTaskAbove)
                .accessibilityLabel("New task")
        }
        .frame(maxWidth: .infinity, minHeight: 33, maxHeight: 33)
        .padding(.leading, CGFloat(task.indentLevel) * 24 - 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .onChange(of: isAddingTaskAbove) { wasFocused, isFocused in
            guard wasFocused, !isFocused else { return }
            saveTaskAboveIfNeeded()
        }
    }

    private func swipeActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private static let newTaskSlotID = "new-task-slot"

    private func move(from source: IndexSet, to destination: Int) {
        let visibleIndices = visibleTaskIndices
        guard let visibleSource = source.first,
              visibleIndices.indices.contains(visibleSource) else { return }
        let sourceIndex = visibleIndices[visibleSource]
        let destinationIndex = destination < visibleIndices.count
            ? visibleIndices[destination]
            : tasks.count
        let task = tasks[sourceIndex]
        Swift.Task {
            _ = try? await appModel.move(
                taskID: task.id,
                in: tasks,
                from: IndexSet(integer: sourceIndex),
                to: destinationIndex
            )
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        let visible = visibleTasks
        guard let offset = offsets.first, visible.indices.contains(offset) else { return }
        deleteTask(visible[offset].task.id)
    }

    private func deleteTask(_ taskID: TaskID) {
        Swift.Task { try? await appModel.delete(taskID: taskID) }
    }

    private func move(taskID: TaskID, by offset: Int) async {
        guard let sourceIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let parentID = TaskHierarchy.parentID(at: sourceIndex, in: tasks)
        let siblings = tasks.indices.filter { index in
            tasks[index].indentLevel == tasks[sourceIndex].indentLevel
                && TaskHierarchy.parentID(at: index, in: tasks) == parentID
        }
        guard let siblingIndex = siblings.firstIndex(of: sourceIndex) else { return }
        let destination: Int
        if offset < 0 {
            guard siblingIndex > siblings.startIndex else { return }
            destination = siblings[siblingIndex - 1]
        } else {
            guard siblingIndex + 1 < siblings.endIndex else { return }
            let nextSibling = siblings[siblingIndex + 1]
            destination = TaskHierarchy.subtreeRange(startingAt: nextSibling, in: tasks).upperBound
        }
        _ = try? await appModel.move(
            taskID: taskID,
            in: tasks,
            from: IndexSet(integer: sourceIndex),
            to: destination
        )
    }

    private func changeIndentation(taskID: TaskID, outdent: Bool) async {
        _ = try? await appModel.changeIndentation(
            taskID: taskID,
            in: tasks,
            outdent: outdent
        )
    }

    private var visibleTaskIndices: [Int] {
        Self.visibleTaskIndices(in: tasks, collapsedTaskIDs: collapsedTaskIDs)
    }

    private var visibleTasks: [VisibleTask] {
        visibleTaskIndices.map { VisibleTask(index: $0, task: tasks[$0]) }
    }

    static func visibleTaskIndices(
        in tasks: [TildoneDomain.Task],
        collapsedTaskIDs: Set<TaskID>
    ) -> [Int] {
        var indices: [Int] = []
        var collapsedIndentLevel: Int?

        for index in tasks.indices {
            let task = tasks[index]
            if let collapsedIndentLevel {
                if task.indentLevel > collapsedIndentLevel { continue }
            }
            collapsedIndentLevel = nil
            indices.append(index)
            if collapsedTaskIDs.contains(task.id),
               TaskHierarchy.hasSubtasks(at: index, in: tasks) {
                collapsedIndentLevel = task.indentLevel
            }
        }
        return indices
    }

    private func toggleSubtasks(at index: Int) {
        guard tasks.indices.contains(index),
              TaskHierarchy.hasSubtasks(at: index, in: tasks) else { return }
        let taskID = tasks[index].id
        if collapsedTaskIDs.remove(taskID) == nil {
            let subtree = TaskHierarchy.subtreeRange(startingAt: index, in: tasks)
            if let focusedTask,
               tasks[subtree].dropFirst().contains(where: { $0.id == focusedTask }) {
                self.focusedTask = nil
            }
            collapsedTaskIDs.insert(taskID)
        }
    }

}

#Preview("Checklist") {
    let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    let noteID = NoteID(UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
    let model = TildoneiOSApplicationModel(
        repositoryFactory: { _ in
            try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceID)))
        },
        accountResolver: { CloudAccountSnapshot(state: .available, workspaceID: workspaceID) },
        synchronizationEnabled: false
    )

    NavigationStack {
        ChecklistView(appModel: model, noteID: noteID)
    }
    .task {
        guard (try? await model.openForTesting(workspaceID: workspaceID)) != nil,
              (try? await model.createNote(title: "Weekend plans", id: noteID)) != nil,
              let firstTask = try? await model.addTask(
                  noteID: noteID,
                  text: "Book the first appointment",
                  after: []
              ) else { return }
        _ = try? await model.addTask(
            noteID: noteID,
            text: "Pick up flowers",
            after: [firstTask]
        )
    }
}
