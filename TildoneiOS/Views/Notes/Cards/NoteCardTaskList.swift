import Foundation
import SwiftUI
import TildoneDomain

struct NoteCardTaskList: View {
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
                                .padding(.top, 2)
                            } else {
                                TaskCheckboxIndicator(
                                    isChecked: task.isCompleted,
                                    diameter: baseCheckboxSize * contentScale * NoteListMetrics.checboxScale
                                )
                                .padding(.top, 2)
                            }
                            Text(PreviewTaskTextLinks.displayText(for: task.text) ?? AttributedString(task.text))
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

private enum PreviewTaskTextLinks {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func displayText(for text: String) -> AttributedString? {
        guard let detector else { return nil }
        let matches = detector.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        var displayText = AttributedString()
        var cursor = text.startIndex
        var foundURL = false

        for match in matches {
            guard let range = Range(match.range, in: text),
                  let destination = match.url,
                  let scheme = destination.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let host = destination.host,
                  !host.isEmpty else {
                continue
            }
            let displayHost = host.lowercased().hasPrefix("www.")
                ? String(host.dropFirst(4))
                : host
            displayText += AttributedString(String(text[cursor..<range.lowerBound]))
            var linkText = AttributedString(displayHost)
            linkText.link = destination
            linkText.foregroundColor = .accentColor
            displayText += linkText
            cursor = range.upperBound
            foundURL = true
        }

        guard foundURL else { return nil }
        displayText += AttributedString(String(text[cursor...]))
        return displayText
    }
}
