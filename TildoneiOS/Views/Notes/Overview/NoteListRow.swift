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
            : String(localized: "Untitled Note")
    }

    var body: some View {
        Group {
            if note.kind == .singleTask {
                singleTaskRow
            } else {
                checklistRow
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.kind == .singleTask ? (taskListText ?? String(localized: "New task")) : title)
        .accessibilityValue(accessibilityDescription)
    }

    private var checklistRow: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(note.color.swiftUIColor)
                .frame(width: 12, height: 40)

            HStack(spacing: 13) {
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
        }
        .padding(.leading, 4)
    }

    private var singleTaskRow: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(note.color.swiftUIColor)
            Text(taskListText?.isEmpty == false ? taskListText! : String(localized: "New task"))
                .font(.custom("BradleyHandITCTT-Bold", size: 25))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .strikethrough(summary?.isComplete == true)
                .opacity(summary?.isComplete == true ? 0.6 : 1)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 42)
            Image(systemName: summary?.isComplete == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(.black.opacity(0.7))
                .padding(10)
        }
        .frame(minHeight: 72)
    }

    private var accessibilityDescription: String {
        let completion = summary?.accessibilityDescription ?? String(localized: "No tasks")
        guard let taskListText, !taskListText.isEmpty else { return completion }
        return String(localized: "\(completion). Tasks: \(taskListText)")
    }
}

extension NoteColor {
    var swiftUIColor: Color {
        switch self {
        case .yellow: Color(red: 1.00, green: 0.94, blue: 0.63)
        case .green: Color(red: 0.73, green: 1.00, blue: 0.72)
        case .blue: Color(red: 0.68, green: 0.82, blue: 0.95)
        case .pink: Color(red: 0.98, green: 0.78, blue: 0.86)
        case .purple: Color(red: 0.84, green: 0.76, blue: 0.96)
        case .orange: Color(red: 0.99, green: 0.84, blue: 0.70)
        }
    }

    var localizedLabel: LocalizedStringResource {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        case .purple: "Purple"
        case .orange: "Orange"
        }
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
