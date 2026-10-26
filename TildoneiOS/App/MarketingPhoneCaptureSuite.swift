#if MARKETING_CAPTURE && targetEnvironment(simulator)
import SwiftUI
import UIKit
import TildoneDomain
import TildonePersistence

/// Production views with disposable content. Never changes an entitlement or
/// starts StoreKit/CloudKit. Existing Pro examples are seeded into memory.
@MainActor
final class MarketingPhoneCaptureSuite: NSObject {
    static let stories = Set((2...6).map { "ios-screenshot-\($0)" } + ["ios-preview-1", "ios-preview-2"])
    let model: TildoneiOSApplicationModel
    let story: String
    private var selectedNoteID: NoteID?
    private var events: [[String: Any]] = []
    private var searchQuery = ""
    private var greenCarouselFronts: [[String: Any]] = []
    private var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var windows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    }
    private static func text(_ key: String) -> String { NSLocalizedString(key, comment: "Isolated marketing content") }

    init(model: TildoneiOSApplicationModel, story: String) {
        self.model = model
        self.story = story
        super.init()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func deckFrontChanged(_ notification: Notification) {
        guard let info = notification.userInfo, let id = info["id"] as? String,
              greenCarouselFronts.last?["id"] as? String != id else { return }
        greenCarouselFronts.append(["id": id, "title": info["title"] as? String ?? "",
                                    "index": info["index"] as? Int ?? -1])
    }

    static func seed(_ repository: TildoneRepository, story: String) async throws {
        let date = Date(timeIntervalSince1970: 1_770_000_000)
        func add(_ title: String?, _ color: NoteColor, _ items: [(String, Int, Bool)],
                 memo: Bool = false, styled: Bool = false, index: Int = 0) async throws {
            let id: NoteID
            if ["ios-preview-1", "ios-screenshot-3"].contains(story) {
                // All mock task edits share a timestamp. Stable fixture IDs
                // establish the shipping overview's tie-break order.
                guard let uuid = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) else {
                    throw NSError(domain: "MarketingPhoneSuite", code: 5)
                }
                id = NoteID(uuid)
            } else {
                id = NoteID()
            }
            _ = try await repository.createNote(id: id, createdAt: date.addingTimeInterval(-Double(index) * 60),
                                                title: title.map(text), color: color)
            var order: OrderToken?
            for (key, depth, done) in items {
                let token = try OrderToken.between(order, nil)
                let task = try await repository.addTask(id: TaskID(), to: id, createdAt: date,
                                                       text: text(key), orderToken: token, indentLevel: depth)
                if done { _ = try await repository.setTaskCompletion(id: task.id, completion: .completed(at: date)) }
                if styled {
                    let value = text(key)
                    let fragment: String
                    let attributes: RichTextAttributes
                    switch key {
                    case "Make room for ideas":
                        fragment = text("ideas")
                        attributes = RichTextAttributes(styles: [.bold], foregroundColor: .blue)
                    case "Keep what matters in sight":
                        fragment = text("what matters")
                        attributes = RichTextAttributes(styles: [.italic], foregroundColor: .green)
                    case "Take a quiet moment":
                        fragment = text("quiet")
                        attributes = RichTextAttributes(styles: [.bold, .italic], foregroundColor: .purple)
                    default:
                        throw NSError(domain: "MarketingPhoneSuite", code: 2)
                    }
                    guard let selected = value.range(of: fragment), fragment.utf16.count < value.utf16.count else {
                        throw NSError(domain: "MarketingPhoneSuite", code: 3)
                    }
                    let selection = NSRange(selected, in: value)
                    let range = RichTextRange(location: selection.location, length: selection.length)
                    _ = try await repository.editTask(id: task.id, richText: RichText(text: value,
                        spans: [RichTextSpan(range: range, attributes: attributes)]))
                }
                if memo {
                    let value = text(key)
                    let fragment = text("space")
                    guard let selected = value.range(of: fragment), fragment.utf16.count < value.utf16.count else {
                        throw NSError(domain: "MarketingPhoneSuite", code: 4)
                    }
                    let selection = NSRange(selected, in: value)
                    _ = try await repository.editTask(id: task.id, richText: RichText(text: value,
                        spans: [RichTextSpan(range: RichTextRange(location: selection.location, length: selection.length),
                                            attributes: RichTextAttributes(foregroundColor: .blue))]))
                }
                order = token
            }
            if memo {
                _ = try await repository.setNoteKind(id: id, kind: .singleTask)
                _ = try await repository.setSingleMemoFont(id: id, font: .permanentMarker)
            }
        }
        if story == "ios-screenshot-2" {
            try await add("Weekend", .blue, [("Choose a walking route", 0, false), ("Check the train times", 0, false)])
        } else if ["ios-screenshot-5", "ios-screenshot-6", "ios-preview-2"].contains(story) {
            if story != "ios-screenshot-6" {
                try await add("Seaside getaway", .yellow, [
                    ("Plan the journey", 0, false), ("Receive train tickets", 1, true),
                    ("Check station directions", 1, false), ("Pack a bag", 0, false),
                    ("Pack a charger", 1, false), ("Choose a coastal walk", 0, false)
                ])
            }
            if story != "ios-screenshot-5" {
                try await add(nil, .pink, [("Make\nspace.", 0, false)], memo: true, index: 1)
                if story == "ios-preview-2" {
                    try await add("A little space to think", .purple, [("Make room for ideas", 0, false),
                        ("Keep what matters in sight", 0, false), ("Take a quiet moment", 0, false)], styled: true, index: 2)
                }
            }
        } else if story == "ios-preview-1" {
            // Personal plans and work references form two real color decks;
            // meal planning is the one approved yellow note.
            // Reuse the shipping grouping rather than drawing marketing cards.
            try await add("Weekend", .green, [("Book a table", 0, true), ("Check the train times", 0, false),
                                              ("Choose a walking route", 0, false), ("Pack a charger", 0, false)])
            try await add("Work", .blue, [("Add the summary", 0, false), ("Send the proposal", 0, false)], index: 1)
            try await add("Research", .blue, [("Read a chapter", 0, false), ("Save a good idea", 0, false)], index: 2)
            try await add("Dinner plans", .yellow, [("Pick up fresh pasta", 0, false), ("Bring dessert", 0, false)], index: 3)
            try await add("Home", .green, [("Call the electrician", 0, true), ("Pick up the parcel", 0, false)], index: 4)
            try await add("Travel", .green, [("Book train tickets", 0, false), ("Pack a bag", 0, false)], index: 5)
        } else if story == "ios-screenshot-3" {
            // Three green notes form the first native deck. The singleton
            // blue/yellow notes share the second shipping carousel.
            try await add("Weekend", .green, [("Book a table", 0, true), ("Check the train times", 0, false),
                                              ("Choose a walking route", 0, false), ("Pack a charger", 0, false)])
            try await add("Work", .blue, [("Add the summary", 0, false), ("Send the proposal", 0, false)], index: 1)
            try await add("Dinner plans", .yellow, [("Pick up fresh pasta", 0, false), ("Bring dessert", 0, false)], index: 2)
            try await add("Home", .green, [("Call the electrician", 0, true), ("Pick up the parcel", 0, false)], index: 3)
            try await add("Travel", .green, [("Book train tickets", 0, false), ("Pack a bag", 0, false)], index: 4)
        } else {
            try await add("Weekend", .pink, [("Book a table", 0, true), ("Check the train times", 0, false),
                                             ("Choose a walking route", 0, false), ("Pack a charger", 0, false)])
            try await add("Home", .blue, [("Call the electrician", 0, true), ("Pick up the parcel", 0, false)], index: 1)
            try await add("Work", .yellow, [("Add the summary", 0, false), ("Send the proposal", 0, false)], index: 2)
            try await add("Travel", .green, [("Book train tickets", 0, false), ("Pack a bag", 0, false)], index: 3)
            try await add("Reading", .purple, [("Read a chapter", 0, false), ("Save a good idea", 0, false)], index: 4)
            try await add("Dinner plans", .orange, [("Pick up fresh pasta", 0, false), ("Bring dessert", 0, false)], index: 5)
        }
    }

    func run() async throws {
        NotificationCenter.default.addObserver(self, selector: #selector(deckFrontChanged(_:)),
            name: Notification.Name("TildoneMarketingDeckFront"), object: nil)
        try await pause(2)
        if story.hasPrefix("ios-screenshot-") {
            switch story {
            case "ios-screenshot-2", "ios-screenshot-5":
                if let note = model.notes.first { open(note.id) }
            case "ios-screenshot-6":
                if let note = model.notes.first(where: { $0.kind == .singleTask }) { open(note.id) }
            case "ios-screenshot-4":
                searchQuery = Self.text("train")
                post("TildoneMarketingSearch", searchQuery)
            default: break
            }
            try await pause(3)
            for window in windows { window.endEditing(true) }
            try await pause(0.5)
            let screenshotLayout = Bundle.main.infoDictionary?["MarketingOverviewLayout"] as? String ?? "grid"
            try publish(phase: 5, name: "screenshot", layout: story == "ios-screenshot-3" ? screenshotLayout : "list")
            if story == "ios-screenshot-3", Bundle.main.infoDictionary?["MarketingCaptureBothLayouts"] as? Bool == true {
                let deadline = Date().addingTimeInterval(120)
                while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture-deck.txt").path) {
                    guard Date() < deadline else { throw failure("The grid capture did not request its deck companion.") }
                    try await pause(0.1)
                }
                post("TildoneMarketingLayout", "deck")
                try await pause(1)
                try publish(phase: 6, name: "deck-screenshot", layout: "deck")
            }
            return
        }
        try publish(phase: 0, name: "opening", layout: "list")
        let waitDeadline = Date().addingTimeInterval(180)
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("advance.txt").path) {
            guard Date() < waitDeadline else { throw failure("The native recorder did not start.") }
            try await pause(0.1)
        }
        let start = Date()
        func at(_ second: Double) async throws { try await pause(max(0, second - Date().timeIntervalSince(start))) }
        if story == "ios-preview-1" {
            try await at(4)
            post("TildoneMarketingLayout", "grid")
            try await pause(0.7)
            try publish(phase: 1, name: "grid", layout: "grid")
            try await at(9)
            post("TildoneMarketingLayout", "deck")
            try await pause(0.7)
            try publish(phase: 2, name: "deck", layout: "deck")
            try await at(10.5)
            post("TildoneMarketingDeckPan")
            try await at(12.2)
            post("TildoneMarketingDeckPan")
            try await at(14)
            guard let weekend = model.notes.first(where: { $0.title == Self.text("Weekend") }) else { throw failure("Missing mock note.") }
            open(weekend.id)
            try await at(17)
            post("TildoneMarketingFocusNewTask")
            try await pause(0.5)
            try await typeTask(Self.text("Bring a camera"))
            // The real field displays the draft; use the same application-model
            // mutation as its submit action so a capture notification cannot
            // silently lose an asynchronous commit during navigation changes.
            post("TildoneMarketingDismissDraft")
            _ = try await model.addTask(noteID: weekend.id, text: Self.text("Bring a camera"),
                                        after: model.presentation(for: weekend.id).snapshot.tasks)
            try await at(21)
            try publish(phase: 3, name: "captured", layout: "deck")
            if let task = model.presentation(for: weekend.id).snapshot.tasks.first(where: { !$0.isCompleted }) {
                try await model.setCompletion(taskID: task.id, completed: true)
            }
            try await at(23)
            try publish(phase: 4, name: "progress", layout: "deck")
        } else {
            guard let checklist = model.notes.first(where: { $0.title == Self.text("Seaside getaway") }) else { throw failure("Missing mock checklist.") }
            open(checklist.id)
            try await pause(1)
            try publish(phase: 1, name: "subtasks", layout: "list")
            try await at(9)
            if let parent = model.presentation(for: checklist.id).snapshot.tasks.first {
                post("TildoneMarketingCollapseTask", parent.id)
            }
            try await pause(0.7)
            try publish(phase: 2, name: "collapsed", layout: "list")
            try await at(12)
            overview()
            try await pause(0.5)
            guard let styled = model.notes.first(where: { $0.title == Self.text("A little space to think") }) else {
                throw failure("Missing mock styled checklist.")
            }
            open(styled.id)
            try await pause(1)
            try publish(phase: 3, name: "styled-checklist", layout: "list")
            try await at(22)
            overview()
            try await pause(0.5)
            guard let memo = model.notes.first(where: { $0.kind == .singleTask }) else { throw failure("Missing mock memo.") }
            open(memo.id)
            try await pause(1)
            for window in windows { window.endEditing(true) }
            try publish(phase: 4, name: "memo", layout: "list")
        }
        try await at(30)
        try publish(phase: 5, name: "finished", layout: story == "ios-preview-1" ? "deck" : "list")
    }

    private func open(_ id: NoteID) {
        selectedNoteID = id
        post("TildoneMarketingOpenNote", id)
    }
    private func overview() {
        selectedNoteID = nil
        post("TildoneMarketingOverview")
    }
    private func post(_ name: String, _ object: Any? = nil) {
        NotificationCenter.default.post(name: Notification.Name(name), object: object)
    }
    private func pause(_ seconds: Double) async throws {
        if seconds > 0 { try await Swift.Task.sleep(for: .seconds(seconds)) }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "MarketingPhoneSuite", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func typeTask(_ text: String) async throws {
        var prefix = ""
        for character in text {
            prefix.append(character)
            NotificationCenter.default.post(name: Notification.Name("TildoneMarketingTypeTask"), object: nil, userInfo: ["text": prefix])
            try await pause(0.06)
        }
        guard windows.flatMap({ descendants($0) }).compactMap({ $0 as? UITextField }).contains(where: { $0.text == text }) else {
            throw failure("The real new-task field did not display the localized mock draft.")
        }
    }

    private func publish(phase: Int, name: String, layout: String) throws {
        let notes = model.notes.map { note -> [String: Any] in
            let tasks = model.presentation(for: note.id).snapshot.tasks
            return ["title": note.title ?? "", "kind": note.kind.rawValue, "color": note.color.rawValue,
                    "singleMemoFont": note.singleMemoFont.rawValue,
                    "tasks": tasks.map { ["text": $0.text, "completed": $0.isCompleted,
                                          "depth": $0.indentLevel, "styled": !$0.richText.isPlain,
                                          "spans": $0.richText.spans.map { span in
                                              ["location": span.range.location, "length": span.range.length,
                                               "styles": span.attributes.styleNames,
                                               "color": span.attributes.foregroundColorName ?? "default"] as [String: Any]
                                          }] }]
        }
        let selected = selectedNoteID.flatMap { model.presentation(for: $0).snapshot.note }
        let view = selected == nil ? "NotesListView" : (selected?.kind == .singleTask ? "SingleMemoTextView" : "ChecklistView")
        let proof: [String: Any] = [
            "phase": phase, "name": name, "asset": story, "nativeView": view, "layout": layout,
            "nativeUI": true, "mockDataOnly": true, "cloudKitStarted": false, "storeKitStarted": false,
            "proContent": ["ios-screenshot-5", "ios-screenshot-6", "ios-preview-2"].contains(story),
            "locale": Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US",
            "preferredLocalizations": Bundle.main.preferredLocalizations, "notes": notes,
            "selectedTitle": selected?.title ?? "", "searchQuery": searchQuery,
            "greenCarouselFronts": greenCarouselFronts,
            "screenPointSize": windows.first.map { [$0.bounds.width, $0.bounds.height] } ?? [], "verified": !notes.isEmpty
        ]
        events.append(proof)
        try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("capture-events.json"), options: .atomic)
        try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("capture-phase.json"), options: .atomic)
    }
}
#endif
