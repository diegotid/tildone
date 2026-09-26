import SwiftUI
import TildoneDomain

struct ProPreviewScene: View {
    let feature: ProFeature
    let locale: Locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let content = ProPreviewContent(feature: feature, locale: locale)
        ZStack {
            (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
            NoteCard(
                note: content.note,
                summary: NoteTaskSummary(noteID: content.note.id, tasks: TaskHierarchy.leafTasks(in: content.tasks)),
                tasks: content.tasks.enumerated().map { index, task in
                    NoteTaskPreview(task, subtaskProgress: TaskHierarchy.subtaskProgress(at: index, in: content.tasks))
                },
                style: .deck, height: 288, contentScale: 1,
                rename: {}, delete: {}
            )
            .frame(width: 216)
            .environment(\.colorScheme, .light)
        }
        .frame(width: 360, height: 360)
        .allowsHitTesting(false)
    }
}
