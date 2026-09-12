import SwiftUI
import TildoneDomain

struct NoteCard: View {
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

        VStack(alignment: note.kind == .singleTask ? .center : .leading, spacing: 12 * contentScale) {
            if note.kind == .checklist {
                HStack(alignment: .center, spacing: 8 * contentScale) {
                Text(title)
                    .font(.system(size: baseTitleSize * contentScale, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .frame(minHeight: 46)
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
            }

            if note.kind == .singleTask {
                singleTaskPreview
            } else {
                NoteCardTaskList(tasks: tasks, style: style, contentScale: contentScale)
            }
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
        .overlay(alignment: .topTrailing) {
            if note.kind == .singleTask {
                Image(systemName: tasks.first?.isCompleted == true ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20 * contentScale))
                    .foregroundStyle(.black.opacity(0.7))
                    .padding(14 * contentScale)
            }
        }
        .contextMenu {
            if note.kind == .checklist {
                Button("Rename", action: rename)
            }
            if summary?.isEmpty == true {
                Button("Delete", role: .destructive, action: delete)
            }
        }
        .accessibilityLabel(note.kind == .singleTask ? (tasks.first?.text ?? String(localized: "New task")) : title)
        .accessibilityValue(summary?.accessibilityDescription ?? String(localized: "No tasks"))
        .accessibilityHint("Double tap to open the note")
    }

    private var singleTaskPreview: some View {
        GeometryReader { geometry in
            let task = tasks.first
            ViewThatFits(in: .vertical) {
                singleTaskText(task, size: 44 * contentScale)
                singleTaskText(task, size: 36 * contentScale)
                singleTaskText(task, size: 30 * contentScale)
                singleTaskText(task, size: 24 * contentScale)
                singleTaskText(task, size: 18 * contentScale)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
    }

    private func singleTaskText(_ task: NoteTaskPreview?, size: CGFloat) -> some View {
        Text(task.map {
            RichTaskTextEditor.displayText(from: $0.richText, baseColor: .black)
        } ?? AttributedString(String(localized: "New task")))
            .font(.custom(SingleMemoTypography.fontName, size: size))
            .lineSpacing(SingleMemoTypography.lineSpacing(for: size))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .strikethrough(task?.isCompleted == true)
            .opacity(task?.isCompleted == true ? 0.6 : 1)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
