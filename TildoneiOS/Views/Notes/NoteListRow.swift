//
//  NoteListRow.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneDomain

struct NoteListRow: View {
    let note: Note
    let summary: NoteTaskSummary?
    let taskListText: String?

    private var title: String {
        note.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? note.title!
            : "Untitled Note"
    }

    var body: some View {
        HStack(spacing: 21) {
            NoteCompletionGauge(summary: summary)
                .scaleEffect(0.8, anchor: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let taskListText, !taskListText.isEmpty {
                    Text(taskListText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let completion = summary?.accessibilityDescription ?? "No tasks"
        guard let taskListText, !taskListText.isEmpty else { return completion }
        return "\(completion). Tasks: \(taskListText)"
    }
}

#Preview("In Progress") {
    let noteID = NoteID()
    let replicaID = ReplicaID()
    let stamp = VersionStamp(logicalCounter: 1, replicaID: replicaID)
    let createdAt = Date(timeIntervalSinceReferenceDate: 0)
    let note = Note(
        id: noteID,
        createdAt: createdAt,
        title: "Weekend plans",
        titleVersion: stamp,
        lifecycleVersion: stamp,
        lastMeaningfulEditAt: createdAt,
        lastMeaningfulEditVersion: stamp
    )
    let task = TildoneDomain.Task(
        id: TaskID(),
        noteID: noteID,
        createdAt: createdAt,
        text: "Book the first appointment",
        textVersion: stamp,
        completionVersion: stamp,
        orderToken: try! OrderToken(rawValue: "m"),
        orderVersion: stamp,
        lifecycleVersion: stamp
    )

    List {
        NoteListRow(
            note: note,
            summary: NoteTaskSummary(noteID: noteID, tasks: [task]),
            taskListText: "\(task.text), Pick up flowers, Confirm the reservation"
        )
    }
    .listStyle(.plain)
}
