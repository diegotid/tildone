import Foundation
import TildoneDomain

/// A disposable checklist rendered by the real note components.
struct WhatsNewPreviewContent {
    let content: ProPreviewContent

    init(noteColor: NoteColor, movesCompletedTasksToEnd: Bool, locale: Locale = .current) {
        let bundle = ProPreviewContent.localizationBundle(for: locale)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let version = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
        let noteID = NoteID()
        let note = TildoneDomain.Note(
            id: noteID, createdAt: date, title: String(localized: "A little space to think", bundle: bundle, locale: locale),
            titleVersion: version, color: noteColor, lifecycleVersion: version,
            lastMeaningfulEditAt: date, lastMeaningfulEditVersion: version
        )
        var examples: [(String, Bool)] = [
            (String(localized: "Book a table [weekend]", bundle: bundle, locale: locale), false),
            (String(localized: "Pick up flowers", bundle: bundle, locale: locale), true),
            (String(localized: "Make room for ideas", bundle: bundle, locale: locale), false)
        ]
        if movesCompletedTasksToEnd { examples = examples.filter { !$0.1 } + examples.filter { $0.1 } }
        var order: OrderToken?
        let tasks = examples.compactMap { text, completed -> TildoneDomain.Task? in
            guard let token = try? OrderToken.between(order, nil) else { return nil }
            order = token
            return TildoneDomain.Task(
                id: TaskID(), noteID: noteID, createdAt: date,
                richText: RichText(text: text), textVersion: version,
                completion: completed ? .completed(at: date) : .incomplete,
                completionVersion: version, orderToken: token, orderVersion: version,
                lifecycleVersion: version
            )
        }
        content = ProPreviewContent(note: note, tasks: tasks)
    }
}
