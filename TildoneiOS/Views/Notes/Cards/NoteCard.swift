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

        VStack(alignment: .leading, spacing: 12 * contentScale) {
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
