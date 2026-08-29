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
    @FocusState private var focusedTask: TaskID?
    @FocusState private var isAddingTask: Bool
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
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            let canIndent = index > 0
                                && task.indentLevel != tasks[index - 1].indentLevel + 1
                            let canOutdent = task.indentLevel > 0
                            TaskRow(
                                task: task,
                                subtaskProgress: TaskHierarchy.subtaskProgress(at: index, in: tasks),
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
                                onIndent: {
                                    await changeIndentation(taskID: task.id, outdent: false)
                                },
                                onOutdent: {
                                    await changeIndentation(taskID: task.id, outdent: true)
                                },
                                onDelete: {
                                    try? await appModel.delete(taskID: task.id)
                                    await reload()
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
                                        Label("Indent", systemImage: "increase.indent")
                                    }
                                    .tint(.indigo)
                                }
                                if canOutdent {
                                    Button {
                                        Swift.Task {
                                            await changeIndentation(taskID: task.id, outdent: true)
                                        }
                                    } label: {
                                        Label("Outdent", systemImage: "decrease.indent")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Swift.Task { await delete(taskID: task.id) }
                                }
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

    private func move(from source: IndexSet, to destination: Int) {
        guard let task = source.first.map({ tasks[$0] }) else { return }
        Swift.Task {
            _ = try? await appModel.move(
                taskID: task.id,
                in: tasks,
                from: source,
                to: destination
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

    private func delete(taskID: TaskID) async {
        try? await appModel.delete(taskID: taskID)
        await reload()
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
