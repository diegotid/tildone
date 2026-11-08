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
    let taskPreview: NoteTaskPreview?
    @State private var metadataURL: URL?
    @State private var metadataTitle: String?

    private var memoURL: URL? {
        guard note.kind == .singleTask else { return nil }
        return SingleMemoLinkMetadata.url(in: taskPreview?.text ?? taskListText ?? "")
    }

    private var memoPageTitle: String? {
        guard let memoURL else { return nil }
        return (metadataURL == memoURL ? metadataTitle : nil)
            ?? SingleMemoLinkMetadata.cachedTitle(for: memoURL)
    }

    private var title: String? {
        guard let title = note.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
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
        .accessibilityLabel(note.kind == .singleTask ? (memoPageTitle ?? taskListText ?? String(localized: "New task")) : (title ?? taskListText ?? String(localized: "No tasks")))
        .accessibilityValue(accessibilityDescription)
        .task(id: memoURL) {
            let url = memoURL
            metadataURL = url
            metadataTitle = nil
            guard let url else { return }
            let title = await SingleMemoLinkMetadata.title(for: url)
            guard !Swift.Task.isCancelled else { return }
            metadataTitle = title
        }
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
                    if let title {
                        Text(title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                    }
                    if let taskListText, !taskListText.isEmpty {
                        Text(taskListText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(title == nil ? 2 : 1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 4)
    }

    private var singleTaskRow: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(note.color.swiftUIColor)
                .frame(width: 12, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                if let memoPageTitle {
                    Text(verbatim: memoPageTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(singleTaskPreviewText)
                    .font(memoPageTitle == nil ? .body.weight(.medium) : .subheadline)
                    .lineLimit(memoPageTitle == nil ? 2 : 1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 4)
    }

    private var accessibilityDescription: String {
        let completion = summary?.accessibilityDescription ?? String(localized: "No tasks")
        guard let taskListText, !taskListText.isEmpty else { return completion }
        return String(localized: "\(completion). Tasks: \(taskListText)")
    }

    private var singleTaskPreviewText: AttributedString {
        guard let taskPreview else {
            let text = taskListText?.isEmpty == false ? taskListText! : String(localized: "New task")
            return RichTaskTextEditor.displayText(from: RichText(text: text), shortenLinks: true)
        }
        return RichTaskTextEditor.displayText(from: taskPreview.richText, shortenLinks: true)
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
            taskListText: "\(task.text), Pick up flowers, Confirm the reservation",
            taskPreview: NoteTaskPreview(task)
        )
    }
    .listStyle(.plain)
}
