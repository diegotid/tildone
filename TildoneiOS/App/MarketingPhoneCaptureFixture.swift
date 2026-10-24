#if MARKETING_CAPTURE && targetEnvironment(simulator)
import SwiftUI
import UIKit
import TildoneDomain
import TildonePersistence
import TildoneSync

/// Runs the real overview, creation flow and native text fields with mock data.
@MainActor
final class MarketingPhoneCaptureFixture: NSObject, ObservableObject {
    let model: TildoneiOSApplicationModel
    private let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
    private let homeID = NoteID(UUID(uuidString: "00000000-0000-0000-0000-000000000094")!)
    private var sharedNoteID: NoteID?
    private var started = false
    private var startTime: Date?
    private var events: [[String: Any]] = []
    private var keyboardSuppressedFields: Set<ObjectIdentifier> = []
    private var maxSoftwareKeyboardHeight: CGFloat = 0
    private var titleVisibleWhileTypingTask = false
    private var localizedInputVerified = false
    private var deckGeometry: [String: [String: Any]] = [:]
    private var taskPreviewFrames: [String: CGRect] = [:]
    private var cardTitleFrames: [String: CGRect] = [:]
    private var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    override init() {
        let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
        model = TildoneiOSApplicationModel(
            repositoryFactory: { _ in
                try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceID)))
            },
            accountResolver: { CloudAccountSnapshot(state: .available, workspaceID: workspaceID) },
            synchronizationEnabled: false
        )
        super.init()
    }

    func prepare() async {
        guard !started else { return }
        started = true
        do {
            NotificationCenter.default.addObserver(self, selector: #selector(textFieldBeganEditing(_:)),
                name: UITextField.textDidBeginEditingNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("advance.txt"))
            try await model.openForTesting(workspaceID: workspaceID)
            // The story demonstrates a connected account. Supply its mock
            // presentation without starting a CloudKit transport in this fixture.
            model.syncPresentation.update(status: SyncStatus(availability: .available, activity: .idle))
            if Bundle.main.infoDictionary?["MarketingStory"] as? String == "screenshot-2" {
                NotificationCenter.default.addObserver(self, selector: #selector(deckGeometryChanged(_:)),
                    name: Notification.Name("TildoneMarketingDeckGeometry"), object: nil)
                NotificationCenter.default.addObserver(self, selector: #selector(taskPreviewGeometryChanged(_:)),
                    name: Notification.Name("TildoneMarketingTaskPreviewGeometry"), object: nil)
                NotificationCenter.default.addObserver(self, selector: #selector(cardTitleGeometryChanged(_:)),
                    name: Notification.Name("TildoneMarketingCardTitleGeometry"), object: nil)
                try await prepareScreenshot()
                return
            }
            _ = try await model.createNote(title: String(localized: "Home"), id: homeID)
            try await model.setColor(noteID: homeID, color: .blue)
            let first = try await model.addTask(noteID: homeID, text: String(localized: "Call the electrician"), after: [])!
            _ = try await model.addTask(noteID: homeID, text: String(localized: "Pick up the parcel"), after: [first])
            try await Swift.Task.sleep(for: .seconds(1.5))
            try publish(phase: 0, name: "overview")
            try await waitForStart()
            startTime = Date()
            try await wait(until: 3)
            post("TildoneMarketingCreateNote")
            try await wait(until: 4)
            guard let created = model.notes.first(where: { $0.id != homeID }) else {
                throw NSError(domain: "MarketingPhoneCapture", code: 1)
            }
            sharedNoteID = created.id
            try await model.setColor(noteID: created.id, color: .pink)
            try publish(phase: 1, name: "new-note")
            try await wait(until: 4.2)
            try await typeIntoFocusedField(String(localized: "Weekend"), action: "TildoneMarketingTypeTitle")
            try await wait(until: 5.5)
            post("TildoneMarketingSubmitTitle")
            let titleDeadline = Date().addingTimeInterval(1.5)
            while model.presentation(for: created.id).snapshot.note?.title != String(localized: "Weekend"),
                  Date() < titleDeadline {
                try await Swift.Task.sleep(for: .milliseconds(50))
            }
            try await wait(until: 6.1)
            guard model.presentation(for: created.id).snapshot.note?.title == String(localized: "Weekend") else {
                throw NSError(domain: "MarketingPhoneCapture", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "The localized title was not committed by the native editor."])
            }
            try publish(phase: 2, name: "titled")
            post("TildoneMarketingFocusNewTask")
            try await wait(until: 6.8)
            try await typeIntoFocusedField(String(localized: "Book a table"), action: "TildoneMarketingTypeTask")
            try requireNativeTitle(name: "task-entry")
            titleVisibleWhileTypingTask = true
            try await wait(until: 8.6)
            post("TildoneMarketingCommitNewTask")
            try await wait(until: 9.5)
            guard model.presentation(for: created.id).snapshot.tasks.map(\.text) == [String(localized: "Book a table")] else {
                throw NSError(domain: "MarketingPhoneCapture", code: 3)
            }
            try publish(phase: 3, name: "created")
            // This update corresponds to the later Mac edit and completion in
            // the composite. The shared data transport remains scripted/offline.
            try await wait(until: 22)
            let tasks = model.presentation(for: created.id).snapshot.tasks
            guard let firstTask = tasks.first else { throw NSError(domain: "MarketingPhoneCapture", code: 4) }
            _ = try await model.addTask(noteID: created.id, text: String(localized: "Check the train times"), after: tasks)
            try await model.setCompletion(taskID: firstTask.id, completed: true)
            try await wait(until: 22.5)
            try publish(phase: 4, name: "updated")
            try await wait(until: 30.5)
            try publish(phase: 5, name: "complete")
        } catch {
            try? saveFrame(name: "failure")
            try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("capture-events.json"), options: .atomic)
            try? String(describing: error).write(to: directory.appendingPathComponent("capture-error.txt"), atomically: true, encoding: .utf8)
        }
    }

    @objc private func deckGeometryChanged(_ notification: Notification) {
        guard let info = notification.userInfo as? [String: Any], let color = info["color"] as? String else { return }
        deckGeometry[color] = info
    }

    @objc private func taskPreviewGeometryChanged(_ notification: Notification) {
        guard let texts = notification.userInfo?["texts"] as? [String],
              let first = texts.first, let frame = notification.userInfo?["frame"] as? CGRect else { return }
        taskPreviewFrames[first] = frame
    }

    @objc private func cardTitleGeometryChanged(_ notification: Notification) {
        guard let title = notification.userInfo?["title"] as? String,
              let frame = notification.userInfo?["frame"] as? CGRect else { return }
        cardTitleFrames[title] = frame
    }

    private func prepareScreenshot() async throws {
        let fixture: [(String, NoteColor, [(String, Bool)])] = [
            (String(localized: "Dinner plans"), .yellow, [
                (String(localized: "Confirm the guests"), true),
                (String(localized: "Pick up fresh pasta"), false),
                (String(localized: "Bring dessert"), false)
            ]),
            (String(localized: "Shopping"), .yellow, [
                (String(localized: "Coffee beans"), false),
                (String(localized: "Fresh fruit"), false)
            ]),
            (String(localized: "Home"), .blue, [
                (String(localized: "Call the electrician"), true),
                (String(localized: "Pick up the parcel"), false)
            ]),
            (String(localized: "Weekend"), .blue, [
                (String(localized: "Choose a walking route"), false),
                (String(localized: "Check the train times"), false)
            ])
        ]
        var notes: [[String: Any]] = []
        for (title, color, items) in fixture {
            let note = try await model.createNote(title: title)
            try await model.setColor(noteID: note.id, color: color)
            var tasks: [TildoneDomain.Task] = []
            for (text, _) in items {
                guard let task = try await model.addTask(noteID: note.id, text: text, after: tasks) else {
                    throw NSError(domain: "MarketingPhoneCapture", code: 10)
                }
                tasks.append(task)
            }
            for (task, item) in zip(tasks, items) where item.1 {
                try await model.setCompletion(taskID: task.id, completed: true)
            }
            let snapshot = model.presentation(for: note.id).snapshot
            notes.append(["title": snapshot.note?.title ?? "", "color": snapshot.note?.color.rawValue ?? "",
                          "taskTexts": snapshot.tasks.map(\.text),
                          "completedTexts": snapshot.tasks.filter(\.isCompleted).map(\.text)])
            // Let the native overview retain the same creation order as the Mac.
            try await Swift.Task.sleep(for: .milliseconds(150))
        }
        try await Swift.Task.sleep(for: .seconds(3))
        for window in captureWindows { window.endEditing(true) }
        guard let window = captureWindows.first(where: \.isKeyWindow) else {
            throw NSError(domain: "MarketingPhoneCapture", code: 11)
        }
        let safeFrame = window.bounds.inset(by: window.safeAreaInsets)
        var visibleDecks: [[String: Any]] = []
        // The front card of each native deck must show its entire title and
        // task preview. A lower card may extend below the scroll viewport;
        // that is the shipping layout, and is never shrunk for the capture.
        for index in [0, 2] {
            let (title, color, items) = fixture[index]
            guard let geometry = deckGeometry[color.rawValue],
                  geometry["title"] as? String == title,
                  geometry["noteCount"] as? Int == 2,
                  let frame = geometry["frame"] as? CGRect,
                  let viewport = geometry["viewport"] as? CGRect,
                  let cardHeight = geometry["cardHeight"] as? CGFloat,
                  let titleFrame = cardTitleFrames[title],
                  let taskFrame = taskPreviewFrames[items[0].0] else {
                throw NSError(domain: "MarketingPhoneCapture", code: 12,
                              userInfo: [NSLocalizedDescriptionKey: "The native overview did not render both matching color decks."])
            }
            let cardFrame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: cardHeight)
            let visible = viewport.intersection(safeFrame).intersection(cardFrame).insetBy(dx: -1, dy: -1)
            let titleVisible = visible.contains(titleFrame)
            let tasksVisible = visible.contains(taskFrame)
            visibleDecks.append(["title": title, "color": color.rawValue, "noteCount": 2,
                                 "titleVisible": titleVisible, "taskPreviewVisible": tasksVisible,
                                 "fullCardVisible": visible.contains(cardFrame),
                                 "frame": [frame.minX, frame.minY, frame.width, frame.height],
                                 "titleFrame": [titleFrame.minX, titleFrame.minY, titleFrame.width, titleFrame.height],
                                 "taskFrame": [taskFrame.minX, taskFrame.minY, taskFrame.width, taskFrame.height],
                                 "visibleFrame": [visible.minX, visible.minY, visible.width, visible.height]])
        }
        let bothPreviewsVisible = visibleDecks.allSatisfy {
            $0["titleVisible"] as? Bool == true && $0["taskPreviewVisible"] as? Bool == true
        }
        // Measure the real bottom search control. Enlarge the entire native
        // screen in the Mac composition until this edge falls below canvas.
        guard let searchField = descendants(window).compactMap({ $0 as? UISearchTextField })
            .first(where: { field in
                let frame = field.convert(field.bounds, to: window)
                guard frame.minY > window.bounds.height * 0.75, frame.height > 0 else { return false }
                var ancestor: UIView? = field
                while let view = ancestor {
                    if view.isHidden || view.alpha < 0.9 { return false }
                    ancestor = view.superview
                }
                return true
            }) else {
            throw NSError(domain: "MarketingPhoneCapture", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "The native search box could not be measured for the composition crop."])
        }
        let searchFieldFrame = searchField.convert(searchField.bounds, to: window)
        var searchTop = searchFieldFrame.minY
        var ancestor = searchField.superview
        while let view = ancestor {
            if let bar = view as? UISearchBar, !bar.isHidden, bar.bounds.height > 0 {
                let frame = bar.convert(bar.bounds, to: window)
                if frame.minY > window.bounds.height * 0.75 { searchTop = min(searchTop, frame.minY) }
                break
            }
            ancestor = view.superview
        }
        let cropY = searchTop - 2
        let contentAboveCrop = [0, 2].allSatisfy { index in
            let (title, _, items) = fixture[index]
            return (cardTitleFrames[title]?.maxY ?? .infinity) < cropY
                && (taskPreviewFrames[items[0].0]?.maxY ?? .infinity) < cropY
        }
        let status = model.syncPresentation.status
        let payload: [String: Any] = [
            "phase": 5, "asset": "screenshot-2", "screenshotRevision": 3,
            "nativeView": "NotesDeckView", "nativeUI": true,
            "notes": notes, "noteCount": notes.count, "colorCounts": ["yellow": 2, "blue": 2],
            "deckCount": visibleDecks.count, "decks": visibleDecks,
            "nativeTitleVisible": bothPreviewsVisible, "bothDeckPreviewsVisible": bothPreviewsVisible,
            "screenPointSize": [window.bounds.width, window.bounds.height],
            "cropAboveSearchY": cropY, "nativeSearchTop": searchTop, "deckContentAboveCrop": contentAboveCrop,
            "softwareKeyboardHidden": focusedField == nil && maxSoftwareKeyboardHeight < 100,
            "phoneSyncIndicatorConnected": SyncStatusPresentation.symbol(for: status) == "icloud",
            "syncSymbol": SyncStatusPresentation.symbol(for: status),
            "mockDataOnly": true, "cloudKitStarted": false,
            "locale": Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US",
            "preferredLocalizations": Bundle.main.preferredLocalizations
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        // Preserve actual geometry on failure so a framing issue is reviewable.
        try data.write(to: directory.appendingPathComponent("phone-screenshot-result.json"), options: .atomic)
        guard bothPreviewsVisible, contentAboveCrop, cropY > window.bounds.height * 0.75,
              focusedField == nil, maxSoftwareKeyboardHeight < 100,
              SyncStatusPresentation.symbol(for: status) == "icloud" else {
            throw NSError(domain: "MarketingPhoneCapture", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Both native decks need visible titles and task previews, a hidden keyboard and a connected cloud indicator."])
        }
        try data.write(to: directory.appendingPathComponent("capture-phase.json"), options: .atomic)
    }

    private var focusedField: UITextField? {
        captureWindows.flatMap { descendants($0) }.compactMap { $0 as? UITextField }
            .first(where: \.isFirstResponder)
    }

    private func typeIntoFocusedField(_ text: String, action: String) async throws {
        guard focusedField != nil else {
            throw NSError(domain: "MarketingPhoneCapture", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "The real iPhone text field did not receive focus."])
        }
        var prefix = ""
        let interval = min(0.09, 1.4 / Double(max(text.count, 1)))
        for character in text {
            prefix.append(character)
            let started = Date()
            // Feed mock text through the real SwiftUI binding. Injecting UIKit
            // editingChanged events is not the TextField binding contract.
            NotificationCenter.default.post(name: Notification.Name(action), object: nil,
                                            userInfo: ["text": prefix])
            let deadline = started.addingTimeInterval(0.75)
            while focusedField?.text != prefix, Date() < deadline {
                try await Swift.Task.sleep(for: .milliseconds(16))
            }
            guard let field = focusedField, field.text == prefix else {
                try saveInputDiagnostic(expected: prefix, stage: action)
                throw NSError(domain: "MarketingPhoneCapture", code: 9,
                              userInfo: [NSLocalizedDescriptionKey: "The native field did not display the SwiftUI fixture draft."])
            }
            suppressKeyboard(for: field)
            field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
            let remaining = interval - Date().timeIntervalSince(started)
            if remaining > 0 { try await Swift.Task.sleep(for: .seconds(remaining)) }
        }
        localizedInputVerified = true
    }

    private func saveInputDiagnostic(expected: String, stage: String) throws {
        let field = focusedField
        let payload: [String: Any] = [
            "stage": stage, "hasFirstResponder": field != nil,
            "displayedTextMatches": field?.text == expected,
            "expectedCharacterCount": expected.count,
            "displayedCharacterCount": field?.text?.count ?? 0,
            "autocorrectionType": field?.autocorrectionType.rawValue ?? -1,
            "spellCheckingType": field?.spellCheckingType.rawValue ?? -1,
            "mockDataOnly": true
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("input-diagnostic.json"), options: .atomic)
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }

    private var captureWindows: [UIWindow] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    }

    private var nativeTitleVisible: Bool {
        captureWindows.contains { window in
            descendants(window).compactMap { $0 as? UITextField }.contains { field in
                guard field.text == String(localized: "Weekend"),
                      let font = field.font, font.pointSize >= 20 else { return false }
                let textRect = field.textRect(forBounds: field.bounds)
                let frame = field.convert(textRect, to: window)
                let requiredWidth = (String(localized: "Weekend") as NSString)
                    .size(withAttributes: [.font: font]).width
                var ancestor: UIView? = field
                while let view = ancestor {
                    if view.isHidden || view.alpha < 0.9 { return false }
                    if view.clipsToBounds {
                        let visible = view.convert(view.bounds, to: window).intersection(frame)
                        if visible.height < frame.height - 1 || visible.width < frame.width - 1 { return false }
                    }
                    ancestor = view.superview
                }
                return frame.minY > window.safeAreaInsets.top + 30
                    && frame.maxY < window.bounds.height - window.safeAreaInsets.bottom
                    && textRect.width >= requiredWidth && frame.height >= font.lineHeight - 1
                    && frame.minX >= 0 && frame.maxX <= window.bounds.width
            }
        }
    }

    @objc private func textFieldBeganEditing(_ notification: Notification) {
        guard let field = notification.object as? UITextField else { return }
        suppressKeyboard(for: field)
    }

    private func suppressKeyboard(for field: UITextField) {
        guard keyboardSuppressedFields.insert(ObjectIdentifier(field)).inserted else { return }
        // The real field retains focus and native editing. Only this private
        // capture app supplies an empty input view to omit the software keyboard.
        field.inputView = UIView(frame: .zero)
        field.inputAccessoryView = UIView(frame: .zero)
        // The fixture types complete, already-localized mock strings. Prevent
        // the simulator's default keyboard dictionary from rewriting them.
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.reloadInputViews()
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let visible = UIScreen.main.bounds.intersection(frame)
        maxSoftwareKeyboardHeight = max(maxSoftwareKeyboardHeight, visible.isNull ? 0 : visible.height)
    }

    private func post(_ name: String) {
        NotificationCenter.default.post(name: Notification.Name(name), object: nil)
    }

    private func publish(phase: Int, name: String) throws {
        if phase >= 2 { try requireNativeTitle(name: name) }
        let syncStatus = model.syncPresentation.status
        let syncSymbol = SyncStatusPresentation.symbol(for: syncStatus)
        guard syncStatus.availability == .available, syncStatus.activity == .idle,
              syncSymbol == "icloud" else {
            throw NSError(domain: "MarketingPhoneCapture", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "The mock sync indicator is not connected."])
        }
        let snapshot = sharedNoteID.map { model.presentation(for: $0).snapshot }
        let tasks = snapshot?.tasks ?? []
        let payload: [String: Any] = [
            "phase": phase, "frame": name, "mockDataOnly": true, "cloudKitStarted": false,
            "nativeView": phase == 0 ? "NotesListView" : "ChecklistView",
            "taskTexts": tasks.map(\.text), "completedTexts": tasks.filter(\.isCompleted).map(\.text),
            "title": snapshot?.note?.title ?? "", "noteCount": model.notes.count,
            "keyboardSuppressedFields": keyboardSuppressedFields.count,
            "maxSoftwareKeyboardHeight": maxSoftwareKeyboardHeight,
            "nativeTitleVisible": nativeTitleVisible,
            "titlePresentation": "native-creation-field",
            "syncAvailability": syncStatus.availability.rawValue,
            "syncActivity": syncStatus.activity.rawValue,
            "syncSymbol": syncSymbol,
            "titleVisibleWhileTypingTask": titleVisibleWhileTypingTask,
            "localizedInputVerified": localizedInputVerified,
            "inputMethod": "swiftui-binding",
            "preferredLocalizations": Bundle.main.preferredLocalizations,
            "locale": Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US"
        ]
        events.append(payload)
        try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("capture-events.json"), options: .atomic)
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("capture-phase.json"), options: .atomic)
    }

    private func requireNativeTitle(name: String) throws {
        try saveFrame(name: name)
        guard nativeTitleVisible else {
            throw NSError(domain: "MarketingPhoneCapture", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "The native note title is collapsed or truncated."])
        }
    }

    private func saveFrame(name: String) throws {
        guard let window = captureWindows.first(where: \.isKeyWindow) else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try image.pngData()?.write(to: directory.appendingPathComponent("phone-\(name).png"))
    }

    private func wait(until seconds: Double) async throws {
        let remaining = seconds - Date().timeIntervalSince(startTime!)
        if remaining > 0 { try await Swift.Task.sleep(for: .seconds(remaining)) }
    }

    private func waitForStart() async throws {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if let value = try? String(contentsOf: directory.appendingPathComponent("advance.txt"), encoding: .utf8),
               value.trimmingCharacters(in: .whitespacesAndNewlines) == "1" { return }
            try await Swift.Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "MarketingPhoneCapture", code: 6)
    }
}
#endif
