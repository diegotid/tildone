//
//  HelpMenuSearchProvider.swift
//  Tildone
//

import AppKit
import Foundation

enum HelpMenuTopic: Hashable {
    case gatherNotes
    case noteDimming
}

struct HelpMenuSearchCatalog {
    private let locale: Locale
    private let bundle: Bundle

    init(locale: Locale = .current, bundle: Bundle = Bundle(for: HelpMenuSearchProvider.self)) {
        self.locale = locale
        self.bundle = bundle
    }

    func matchingTopics(for searchString: String, limit: Int) -> [HelpMenuTopic] {
        guard limit > 0, !searchString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return HelpMenuTopic.allCases
            .filter { matches(searchString, topic: $0) }
            .prefix(limit)
            .map { $0 }
    }

    func localizedTitles(for topic: HelpMenuTopic) -> [String] {
        [localized("Scroll Gestures"), localized(topic.titleKey)]
    }

    private func matches(_ searchString: String, topic: HelpMenuTopic) -> Bool {
        let query = normalized(searchString)
        return ([localized(topic.titleKey)] + localized(topic.aliasesKey)
            .split(separator: ",")
            .map(String.init))
            .contains { normalized($0).contains(query) }
    }

    private func localized(_ key: String) -> String {
        let requestedLanguage = locale.language.languageCode?.identifier
        let localization = bundle.localizations.first { $0 == locale.identifier }
            ?? bundle.localizations.first { $0 == requestedLanguage }
        guard let localization,
              let path = bundle.path(forResource: localization, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        }
        return localizedBundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    private func normalized(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
    }
}

private extension HelpMenuTopic {
    static let allCases: [HelpMenuTopic] = [.gatherNotes, .noteDimming]

    var titleKey: String {
        switch self {
        case .gatherNotes: "Gather Notes"
        case .noteDimming: "Note Dimming"
        }
    }

    var aliasesKey: String {
        switch self {
        case .gatherNotes: "Help search aliases: Gather Notes"
        case .noteDimming: "Help search aliases: Note Dimming"
        }
    }
}

final class HelpMenuSearchProvider: NSObject, NSUserInterfaceItemSearching {
    private let action: (HelpMenuTopic) -> Void

    init(action: @escaping (HelpMenuTopic) -> Void = HelpMenuSearchProvider.openScrollGesturesHelp) {
        self.action = action
    }

    func searchForItems(
        withSearch searchString: String,
        resultLimit: Int,
        matchedItemHandler handleMatchedItems: @escaping ([Any]) -> Void
    ) {
        handleMatchedItems(HelpMenuSearchCatalog().matchingTopics(for: searchString, limit: resultLimit))
    }

    func localizedTitles(forItem item: Any) -> [String] {
        guard let topic = item as? HelpMenuTopic else { return [] }
        return HelpMenuSearchCatalog().localizedTitles(for: topic)
    }

    func performAction(forItem item: Any) {
        guard let topic = item as? HelpMenuTopic else { return }
        DispatchQueue.main.async { [action] in
            action(topic)
        }
    }

    private static func openScrollGesturesHelp(for topic: HelpMenuTopic) {
        NotificationCenter.default.post(name: .openScrollGesturesHelp, object: nil)
    }
}
