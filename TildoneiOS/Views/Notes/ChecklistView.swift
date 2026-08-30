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
    @ObservedObject var appModel: TildoneiOSApplicationModel
    let noteID: NoteID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    @State private var note: Note?
    @State private var tasks: [Task] = []
    @State private var newTaskText = ""
    @State private var title = ""
    @State private var titleBaseline: String?
    @State private var collapsedTaskIDs: Set<TaskID> = []
    @State private var taskInsertionTargetID: TaskID?
    @State private var taskInsertionText = ""
    @FocusState private var focusedTask: TaskID?
    @FocusState private var isAddingTask: Bool
    @FocusState private var isAddingTaskAbove: Bool
    @FocusState private var isEditingTitle: Bool

    private var isInEditMode: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var isUntitled: Bool {
        note?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private var canEditTasks: Bool {
        Self.normalizedTitle(title) != nil || !tasks.isEmpty
    }

    var body: some View {
        Group {
            if let note {
                List {
                    if isInEditMode || isEditingTitle || isUntitled {
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
                                && task.indentLevel != tasks[index - 1].indentLevel + 1
                            let canOutdent = task.indentLevel > 0
                            if taskInsertionTargetID == task.id {
                                taskInsertionRow(above: task)
                            }
                            TaskRow(
                                task: task,
                                subtaskProgress: TaskHierarchy.subtaskProgress(at: index, in: tasks),
                                subtasksExpanded: hasSubtasks
                                    ? !collapsedTaskIDs.contains(task.id)
                                    : nil,
                                canIndent: canIndent,
                                canOutdent: canOutdent,
                                focusedTask: $focusedTask,
                                onCommit: { value in
                                    try? await appModel.edit(taskID: task.id, text: value)
                                    await reload()
                                },
                                onToggle: {
                                    try? await appModel.setCompletion(taskID: task.id, completed: !task.isCompleted)
                                    await reload()
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
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if canIndent {
                                    Button {
                                        Swift.Task {
                                            await changeIndentation(taskID: task.id, outdent: false)
                                        }
                                    } label: {
                                        Image(systemName: "increase.indent")
                                    }
                                    .tint(.indigo)
                                    .accessibilityLabel("Indent task")
                                }
                                if canOutdent {
                                    Button {
                                        Swift.Task {
                                            await changeIndentation(taskID: task.id, outdent: true)
                                        }
                                    } label: {
                                        Image(systemName: "decrease.indent")
                                    }
                                    .tint(.blue)
                                    .accessibilityLabel("Outdent task")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    beginAddingTask(above: task.id)
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .tint(.green)
                                .accessibilityLabel("Add Above")
                            }
                        }
                        .onMove(perform: move)

                        TextField("New task", text: $newTaskText)
                            .focused($isAddingTask)
                            .submitLabel(.next)
                            .onSubmit { addTask() }
                            .accessibilityLabel("New task")
                            .frame(minHeight: 33, maxHeight: 33)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(note.color.swiftUIColor.opacity(0.22))
                .navigationTitle(isUntitled ? "" : note.title!)
                .navigationBarTitleDisplayMode(isUntitled ? .inline : .large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Note color", selection: Binding(
                                get: { note.color },
                                set: { color in
                                    Swift.Task {
                                        try? await appModel.setColor(noteID: noteID, color: color)
                                        await reload()
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
                    if canEditTasks {
                        ToolbarItem(placement: .topBarTrailing) { EditButton() }
                    }
                }
                .onDisappear {
                    saveTitle()
                    saveNewTaskIfNeeded()
                    saveTaskAboveIfNeeded()
                }
            } else {
                ContentUnavailableView("This note was deleted", systemImage: "trash")
            }
        }
        .task {
            await reload()
            isEditingTitle = isUntitled
            isAddingTask = !isUntitled && tasks.isEmpty
        }
        .onChange(of: appModel.contentRevision) { _, _ in
            if !appModel.notes.contains(where: { $0.id == noteID }) { dismiss() }
            else { Swift.Task { await reload() } }
        }
    }

    private func reload() async {
        note = appModel.notes.first(where: { $0.id == noteID })
        guard note != nil else { return }
        tasks = (try? await appModel.tasks(in: noteID)) ?? []
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
            await reload()
        }
    }

    private func finishTitleEditing() {
        if Self.normalizedTitle(title) == titleBaseline {
            title = note?.title ?? ""
            titleBaseline = Self.normalizedTitle(note?.title)
        } else {
            saveTitle()
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
            await reload()
            isAddingTask = true
        }
    }

    private func saveNewTaskIfNeeded() {
        let text = newTaskText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        newTaskText = ""
        Swift.Task {
            _ = try? await appModel.addTask(noteID: noteID, text: text, after: tasks)
            await reload()
        }
    }

    private func beginAddingTask(above taskID: TaskID) {
        saveTaskAboveIfNeeded()
        focusedTask = nil
        taskInsertionText = ""
        taskInsertionTargetID = taskID
        Swift.Task {
            await Swift.Task.yield()
            guard taskInsertionTargetID == taskID else { return }
            isAddingTaskAbove = true
        }
    }

    private func cancelAddingTaskAbove() {
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
            await reload()
        }
    }

    private func taskInsertionRow(above task: TildoneDomain.Task) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: 32, height: 33)
            TextField("New task", text: $taskInsertionText)
                .focused($isAddingTaskAbove)
                .submitLabel(.done)
                .onSubmit(addTaskAbove)
                .accessibilityLabel("New task")
        }
        .frame(maxWidth: .infinity, minHeight: 33, maxHeight: 33)
        .padding(.leading, CGFloat(task.indentLevel) * 24)
        .onChange(of: isAddingTaskAbove) { wasFocused, isFocused in
            guard wasFocused, !isFocused else { return }
            saveTaskAboveIfNeeded()
        }
    }

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
            await reload()
        }
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
        await reload()
    }

    private func changeIndentation(taskID: TaskID, outdent: Bool) async {
        _ = try? await appModel.changeIndentation(
            taskID: taskID,
            in: tasks,
            outdent: outdent
        )
        await reload()
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

    private struct VisibleTask: Identifiable {
        let index: Int
        let task: TildoneDomain.Task

        var id: TaskID { task.id }
    }
}

private struct NoteColorPickerSymbol: View {
    let color: NoteColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                        center: .center
                    ),
                    lineWidth: 2.5
                )
            Circle()
                .fill(color.swiftUIColor)
                .padding(5)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.18), lineWidth: 0.5)
                        .padding(5)
                }
        }
        .frame(width: 24, height: 24)
    }
}

private enum NoteColorMenuSwatch {
    static func image(for color: NoteColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 14))
        return renderer.image { context in
            let circle = CGRect(x: 1, y: 1, width: 12, height: 12)
            context.cgContext.setFillColor(UIColor(color.swiftUIColor).cgColor)
            context.cgContext.fillEllipse(in: circle)
            context.cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            context.cgContext.setLineWidth(1)
            context.cgContext.strokeEllipse(in: circle.insetBy(dx: 0.5, dy: 0.5))
        }
        .withRenderingMode(.alwaysOriginal)
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
