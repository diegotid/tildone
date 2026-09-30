import Foundation
import TildoneDomain

/// Ephemeral examples only: no repository, user defaults, or CloudKit access.
struct ProPreviewContent {
    let note: TildoneDomain.Note
    let tasks: [TildoneDomain.Task]

    init(note: TildoneDomain.Note, tasks: [TildoneDomain.Task]) {
        self.note = note
        self.tasks = tasks
    }

    init(feature: ProFeature, locale: Locale, noteColor: NoteColor = .yellow) {
        // String(localized:locale:) uses locale for formatting, not language
        // selection. Select the matching catalog bundle for preview examples.
        let bundle = Self.localizationBundle(for: locale)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let version = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
        let noteID = NoteID()
        note = TildoneDomain.Note(
            id: noteID, createdAt: date,
            title: feature == .singleMemo ? nil : String(localized: "A little space to think", bundle: bundle, locale: locale),
            titleVersion: version, color: noteColor,
            kind: feature == .singleMemo ? .singleTask : .checklist,
            singleMemoFont: .overlock,
            lifecycleVersion: version, lastMeaningfulEditAt: date,
            lastMeaningfulEditVersion: version
        )
        let examples: [(String, Int, Bool)]
        switch feature {
        case .singleMemo:
            examples = [(String(localized: "Remember to call the electrician on Monday", bundle: bundle, locale: locale), 0, false)]
        case .subtasks:
            examples = [
                (String(localized: "Plan a weekend away", bundle: bundle, locale: locale), 0, false),
                (String(localized: "Choose a place", bundle: bundle, locale: locale), 1, true),
                (String(localized: "Book the trip", bundle: bundle, locale: locale), 1, false),
                (String(localized: "Pack a bag", bundle: bundle, locale: locale), 0, false)
            ]
        default:
            examples = [
                (String(localized: "Make room for ideas", bundle: bundle, locale: locale), 0, false),
                (String(localized: "Keep what matters in sight", bundle: bundle, locale: locale), 0, false),
                (String(localized: "Take a quiet moment", bundle: bundle, locale: locale), 0, false)
            ]
        }
        var order: OrderToken?
        tasks = examples.enumerated().compactMap { index, example -> TildoneDomain.Task? in
            guard let token = try? OrderToken.between(order, nil) else { return nil }
            order = token
            var text = RichText(text: example.0)
            if feature == .textStyling {
                let attributes: RichTextAttributes
                switch index {
                case 0: attributes = RichTextAttributes(styles: [.bold])
                case 1: attributes = RichTextAttributes(foregroundColor: .blue)
                default: attributes = RichTextAttributes(styles: [.italic], highlightColor: noteColor == .pink ? .yellow : .pink)
                }
                let word: String
                switch index {
                case 0: word = String(localized: "ideas", bundle: bundle, locale: locale)
                case 1: word = String(localized: "matters", bundle: bundle, locale: locale)
                default: word = String(localized: "quiet", bundle: bundle, locale: locale)
                }
                let wordRange = (example.0 as NSString).range(of: word)
                text = RichText(text: example.0, spans: [RichTextSpan(
                    range: RichTextRange(location: wordRange.location, length: wordRange.length),
                    attributes: attributes
                )])
            }
            return TildoneDomain.Task(
                id: TaskID(), noteID: noteID, createdAt: date,
                richText: text, textVersion: version,
                completion: example.2 ? .completed(at: date) : .incomplete,
                completionVersion: version, orderToken: token, orderVersion: version,
                indentLevel: example.1, lifecycleVersion: version
            )
        }
    }

    static func localizationBundle(for locale: Locale) -> Bundle {
        let language: String
        switch locale.language.languageCode?.identifier {
        case "es": language = "es"
        case "fr": language = "fr"
        case "zh": language = "zh-Hans"
        default: language = "en"
        }
        return Bundle.main.path(forResource: language, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
    }
}
