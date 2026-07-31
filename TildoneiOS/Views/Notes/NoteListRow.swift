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
    let oldestTaskText: String?

    private var title: String {
        note.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? note.title!
            : "Untitled Note"
    }

    var body: some View {
        HStack(spacing: 12) {
            NoteCompletionGauge(summary: summary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let oldestTaskText, !oldestTaskText.isEmpty {
                    Text(oldestTaskText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let completion = summary?.accessibilityDescription ?? "No tasks"
        guard let oldestTaskText, !oldestTaskText.isEmpty else { return completion }
        return "\(completion). Oldest task: \(oldestTaskText)"
    }
}
