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
            try await typeIntoFocusedField(String(localized: "Weekend"))
            try await wait(until: 5.5)
            post("TildoneMarketingSubmitTitle")
            try await wait(until: 6.1)
            guard model.presentation(for: created.id).snapshot.note?.title == String(localized: "Weekend") else {
                throw NSError(domain: "MarketingPhoneCapture", code: 2)
            }
            try publish(phase: 2, name: "titled")
            post("TildoneMarketingFocusNewTask")
            try await wait(until: 6.8)
            try await typeIntoFocusedField(String(localized: "Book a table"))
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
            try? String(describing: error).write(to: directory.appendingPathComponent("capture-error.txt"), atomically: true, encoding: .utf8)
        }
    }

    private func typeIntoFocusedField(_ text: String) async throws {
        let fields = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).flatMap { descendants($0) }.compactMap { $0 as? UITextField }
        guard let field = fields.first(where: \.isFirstResponder) else {
            throw NSError(domain: "MarketingPhoneCapture", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "The real iPhone text field did not receive focus."])
        }
        suppressKeyboard(for: field)
        for character in text {
            field.insertText(String(character))
            field.sendActions(for: .editingChanged)
            try await Swift.Task.sleep(for: .milliseconds(90))
        }
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
