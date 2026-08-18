//
//  Note+Actions.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain
import TildonePersistence

extension Note {
    func handleMinimize() {
        guard let noteWindow else { return }
        let autosaveName = noteWindow.frameAutosaveName
        guard minimizationState.beginMinimizing(
            from: noteWindow.frame,
            autosaveName: autosaveName
        ) else { return }
        NoteWindowFrameAutosavePolicy.suspend(for: noteWindow)
        noteWindow.title = "_" + noteWindow.title
        setColorPickerHidden(true)
        setRestoreControlVisible(true)
        noteWindow.setFrame(minimizedFrame(for: noteWindow), display: true, animate: false)
        NotificationCenter.default.post(name: .arrangeMinimized, object: nil)
    }

    func handleClose() {
        guard note?.isDeletable == true else { return }
        Swift.Task {
            do {
                try await store.deleteNote(noteID)
                UserDefaults.standard.removeObject(forKey: completionAutoDeletionCancellationKey)
            } catch {
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error closing completed note",
                    error: error
                )
            }
        }
    }
}

extension Note {
    func mutate(_ operation: @escaping () async throws -> Void, message: String) {
        Swift.Task {
            do { try await operation() }
            catch {
                // Repository failures must never terminate the user's note window.
                // In particular, a sync/outbox recovery issue must leave locally
                // persisted content available for an explicit recovery decision.
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: message,
                    error: error
                )
            }
        }
    }

    static func mutationFailureMessage(operation: String, error: Error) -> String {
        var result = "Your notes remain on this Mac. Synchronization needs attention before this change can be saved."
#if DEBUG
        result += "\n\nDevelopment detail: \(operation) / \(safePersistenceCategory(error))"
#endif
        return result
    }

    static func safePersistenceCategory(_ error: Error) -> String {
        guard let error = error as? PersistenceError else { return "non-persistence-error" }
        return switch error {
        case .openFailure: "open-failure"
        case .saveFailure: "save-failure"
        case .missing: "missing-entity"
        case .missingPendingMutation: "missing-pending-mutation"
        case .duplicateID: "duplicate-identifier"
        case .ownershipMismatch: "ownership-mismatch"
        case let .malformedRepresentation(_, _, field): "malformed-\(field)"
        case .domainInvariant: "domain-invariant"
        case .unsupportedRecordSchema: "unsupported-schema"
        case .workspaceMismatch: "workspace-mismatch"
        case .workspaceInUse: "workspace-in-use"
        case .invalidWorkspace: "invalid-workspace"
        case .invalidStoreLocation: "invalid-store-location"
        case .invalidQuarantineMetadata: "invalid-quarantine"
        case .atomicMutationFailure: "atomic-mutation-failure"
        case .counterOverflow: "counter-overflow"
        }
    }

    func handleNewTaskCommit() {
        guard !newTaskText.isEmpty else { return }
        let text = newTaskText.capitalizingFirstLetter()
        newTaskText = ""
        mutate({ _ = try await store.addTask(to: noteID, text: text) }, message: "Error on task creation")
    }

    func handleTaskEdit(_ task: TildoneDomain.Task, to text: String) {
        mutate(
            { try await store.editTask(task.id, text: text.capitalizingFirstLetter()) },
            message: "Error on task edit"
        )
    }

    func handleTaskToggle(_ task: TildoneDomain.Task) {
        noteWindow?.makeFirstResponder(nil)
        mutate({
            try await store.setTaskCompletion(
                task.id,
                completed: !task.isCompleted,
                moveToEndWhenCompleted: moveCheckedTasksToEnd
            )
        }, message: "Error on task completion")
    }

    func handleTaskDrop(_ payload: MacTaskDragPayload, at destination: Int) -> Bool {
        guard payload.isValid(for: noteID, taskIDs: tasks.map(\.id)),
              (0...tasks.count).contains(destination) else {
            return false
        }
        mutate(
            { _ = try await store.moveTask(payload.taskID, in: noteID, to: destination) },
            message: "Error reordering task"
        )
        DispatchQueue.main.async {
            taskDropFeedbackResetToken = UUID()
        }
        return true
    }

    func handleTopicEdit(to topic: String) {
        let title = topic.isEmpty ? nil : topic.capitalizingFirstLetter()
        mutate({ try await store.renameNote(noteID, to: title) }, message: "Error on topic edit")
    }

    func handleKeyboard() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window == noteWindow else { return event }
            if (event.keyCode == Keyboard.arrowUp || event.keyCode == Keyboard.arrowDown),
               isEditingNativeTaskField() {
                return event
            }
            if event.keyCode == Keyboard.tabKey, focusedField == .newTask, !newTaskText.isEmpty {
                handleNewTaskCommit(); return nil
            }
            if event.keyCode == Keyboard.arrowUp { handleMoveUp(); return nil }
            if event.keyCode == Keyboard.arrowDown { handleMoveDown(); return nil }
            if event.keyCode == Keyboard.delete, handleDelete() { return nil }
            if event.keyCode == Keyboard.backSpace, handleDelete(isBackwards: true) { return nil }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
                NotificationCenter.default.post(name: .close, object: nil); return nil
            }
            return event
        }
    }

    func isEditingNativeTaskField() -> Bool {
        guard let firstResponder = noteWindow?.firstResponder else { return false }
        return noteWindow?.contentView?.getNestedSubviews().contains { field in
            guard let taskField = field as? MouseSafeTaskNSTextField else { return false }
            return taskField.currentEditor() === firstResponder
        } ?? false
    }

    func handleEnter(for task: TildoneDomain.Task) {
        guard let field = textField(forText: task.text),
              let editor = field.currentEditor() as? NSTextView,
              let cursor = editor.selectedRanges.first?.rangeValue.location,
              let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let insertion = cursor == 0 ? index : index + 1
        insertEmptyTask(at: insertion)
    }

    func insertEmptyTask(at position: Int) {
        skipsNextTaskCountBottomScroll = true
        let emptyTaskIDs = tasks.filter { !$0.isCompleted && $0.text.isEmpty }.map(\.id)
        let removedBeforeInsertion = tasks[..<position].filter {
            !$0.isCompleted && $0.text.isEmpty
        }.count
        Swift.Task {
            do {
                for id in emptyTaskIDs {
                    try await store.deleteTask(id)
                }
                let task = try await store.addTask(
                    to: noteID,
                    text: "",
                    insertingAt: position - removedBeforeInsertion
                )
                focusTaskUsingKeyboard(task.id)
            } catch {
                skipsNextTaskCountBottomScroll = false
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error on task creation",
                    error: error
                )
            }
        }
    }

    func handleMoveUp() {
        guard let id = activeFocusedTaskID else {
            if focusedField == .newTask, let taskID = pendingTasks.last?.id { focusTaskUsingKeyboard(taskID) } else { focusOnNewTask() }
            return
        }
        handleMoveUp(from: id)
    }

    func handleMoveUp(from id: TaskID) {
        guard let index = pendingTasks.firstIndex(where: { $0.id == id }) else { return }
        if index > 0 { focusTaskUsingKeyboard(pendingTasks[index - 1].id) } else { focusOnTopic() }
    }

    func handleMoveDown() {
        guard let id = activeFocusedTaskID else {
            if focusedField == .topic, let taskID = pendingTasks.first?.id { focusTaskUsingKeyboard(taskID) } else { focusOnTopic() }
            return
        }
        handleMoveDown(from: id)
    }

    func handleMoveDown(from id: TaskID) {
        guard let index = pendingTasks.firstIndex(where: { $0.id == id }) else { return }
        if index < pendingTasks.endIndex - 1 { focusTaskUsingKeyboard(pendingTasks[index + 1].id) } else { focusOnNewTask() }
    }

    func handleDelete(isBackwards: Bool = false) -> Bool {
        guard let id = activeFocusedTaskID, let index = pendingTasks.firstIndex(where: { $0.id == id }), pendingTasks[index].text.isEmpty else {
            return false
        }
        let remainingTasks = pendingTasks.filter { $0.id != id }
        let nextIndex = index - (isBackwards ? 1 : 0)
        let nextTaskID: TaskID?
        if remainingTasks.isEmpty {
            nextTaskID = nil
        } else {
            nextTaskID = remainingTasks[
                max(0, min(nextIndex, remainingTasks.count - 1))
            ].id
        }
        skipsNextTaskCountBottomScroll = true
        Swift.Task {
            do {
                try await store.deleteTask(id)
                if let nextTaskID {
                    focusTaskUsingKeyboard(nextTaskID)
                } else {
                    focusOnNewTask()
                }
            } catch {
                skipsNextTaskCountBottomScroll = false
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error on task deletion",
                    error: error
                )
            }
        }
        return true
    }

    func paste(into task: TildoneDomain.Task) {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
        let lines = clipboard.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        guard let first = lines.first, let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        mutate({
            try await store.editTask(task.id, text: first)
            for line in lines.dropFirst().reversed() {
                _ = try await store.addTask(to: noteID, text: line.capitalizingFirstLetter(), insertingAt: index + 1)
            }
        }, message: "Error pasting tasks")
    }

    func handleBringUp() {
        guard let noteWindow, let restoration = minimizationState.beginRestoring() else { return }
        if noteWindow.title.starts(with: "_") {
            noteWindow.title = String(noteWindow.title.dropFirst())
        }
        setColorPickerHidden(false)
        setRestoreControlVisible(false)
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                noteWindow.animator().setFrame(restoration.frame, display: true)
            } completionHandler: {
                Swift.Task { @MainActor in
                    NoteWindowFrameAutosavePolicy.resume(
                        for: noteWindow,
                        using: restoration.autosaveName
                    )
                    minimizationState.finishRestoring()
                }
            }
        }
    }

    func cleanIfRequested(_ notification: Notification) {
        guard let id = notification.object as? NoteID, id == noteID else { return }
        mutate({ try await store.cleanEmptyTasks(in: noteID) }, message: "Error cleaning note")
    }

    func synchronizeCompletionFade(completedAt: Date?) {
        completionFade.synchronize(
            completedAt: completedAt,
            autoDeletionCancelled: completionAutoDeletionWasCancelled(for: completedAt)
        )
        updateTopicVisibility()
        if completionFade.isFading {
            advanceCompletionFade(Date())
        } else if !completionFade.showsCompletionOverlay {
            resetFadeAppearance()
        }
    }

    func advanceCompletionFade(_ date: Date) {
        guard completionFade.isFading else { return }
        fadeAwayProgress = completionFade.progress(
            at: date,
            duration: Timeout.noteFadeOutSeconds
        )
        updateFadeAppearance()
        guard let completedAt = completionFade.beginDeletionIfReady(
            at: date,
            duration: Timeout.noteFadeOutSeconds
        ) else { return }
        deleteCompletedNote(completedAt: completedAt)
    }

    func cancelCompletionFade() {
        completionFade.cancel()
        markCompletionAutoDeletionCancelled()
        updateTopicVisibility()
        resetFadeAppearance()
    }

    func completionAutoDeletionWasCancelled(for completedAt: Date?) -> Bool {
        let defaults = UserDefaults.standard
        let key = completionAutoDeletionCancellationKey
        guard let completedAt else {
            defaults.removeObject(forKey: key)
            return false
        }
        guard let storedTimestamp = defaults.object(forKey: key) as? Double else { return false }
        guard abs(storedTimestamp - completedAt.timeIntervalSinceReferenceDate) < 0.001 else {
            // A new completion cycle should retain its normal grace-period fade.
            defaults.removeObject(forKey: key)
            return false
        }
        return true
    }

    func markCompletionAutoDeletionCancelled() {
        guard let completedAt = note?.completedAt else { return }
        UserDefaults.standard.set(
            completedAt.timeIntervalSinceReferenceDate,
            forKey: completionAutoDeletionCancellationKey
        )
    }

    var completionAutoDeletionCancellationKey: String {
        "cancelledCompletionAutoDeletion.\(noteID.stringValue)"
    }

    func deleteCompletedNote(completedAt: Date) {
        guard note?.completedAt == completedAt else {
            synchronizeCompletionFade(completedAt: note?.completedAt)
            return
        }
        Swift.Task {
            do {
                try await store.deleteNote(noteID)
            } catch {
                completionFade.deletionFailed(completedAt: completedAt)
                resetFadeAppearance()
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error deleting completed note",
                    error: error
                )
            }
        }
    }

    func resetFadeAppearance() {
        fadeAwayProgress = 0
        updateFadeAppearance()
    }

    func updateFadeAppearance() {
        windowAlpha = max(0, 1 - fadeAwayProgress / Timeout.noteFadeOutSeconds)
        let disappearing = windowAlpha < 1
        withAnimation {
            noteWindow?.level = disappearing ? .normal : .floating
            noteWindow?.hasShadow = !disappearing
            setTrafficLightsHidden(disappearing || isMinimized)
            applyCurrentNoteBackground()
        }
    }

    func setTrafficLightsHidden(_ hidden: Bool) {
        noteWindow?.standardWindowButton(.closeButton)?.isHidden = hidden
        noteWindow?.standardWindowButton(.miniaturizeButton)?.isHidden = hidden
        noteWindow?.standardWindowButton(.zoomButton)?.isHidden = hidden
    }

    func updateWindowClosability() {
        noteWindow?.standardWindowButton(.closeButton)?.isEnabled = note?.isDeletable ?? false
    }

    func updateTopicVisibility() {
        withAnimation { isTopicHidden = (note?.title == nil) && (isDone || focusedField != .topic) }
    }

    func applyCurrentNoteBackground() {
        guard let noteWindow else { return }
        let tintAlpha = NoteWindowBackground.tintAlpha(
            configuredAlpha: CGFloat(noteBackgroundOpacity),
            windowAlpha: noteWindow.alphaValue
        )
        noteWindow.applyNoteBackgroundColor(color, alpha: tintAlpha * CGFloat(windowAlpha))
    }

    func applyInitialFocusIfNeeded() {
        guard !didSetInitialFocus, let note, note.tasks.isEmpty, note.title == nil, noteWindow != nil else { return }
        didSetInitialFocus = true
        DispatchQueue.main.async { focusOnTopic() }
    }

    func convertLegacyFontSizeSettingIfNeeded() {
        if fontSize < FontSize.xSmall.rawValue, let size = FontSize(fromLegacySetting: fontSize) { fontSize = size.rawValue }
    }

    func focusTaskUsingKeyboard(_ taskID: TaskID) {
        nativeFocusedTaskID = taskID
        keyboardFocusedTaskID = taskID
        focusedTaskID = taskID
    }

    func activateNativeTask(_ taskID: TaskID) {
        nativeFocusedTaskID = taskID
        focusedTaskID = taskID
    }

    func focusOnTopic() { nativeFocusedTaskID = nil; keyboardFocusedTaskID = nil; focusedTaskID = nil; focusedField = .topic }
    func focusOnNewTask() {
        nativeFocusedTaskID = nil
        keyboardFocusedTaskID = nil
        focusedTaskID = nil
        focusedField = .newTask
        discardUnfilledTaskSlots()
    }

    func discardUnfilledTaskSlots() {
        let emptyTaskIDs = tasks.filter { !$0.isCompleted && $0.text.isEmpty }.map(\.id)
        guard !emptyTaskIDs.isEmpty else { return }
        skipsNextTaskCountBottomScroll = true
        Swift.Task {
            do {
                for id in emptyTaskIDs {
                    try await store.deleteTask(id)
                }
            } catch {
                skipsNextTaskCountBottomScroll = false
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error on task deletion",
                    error: error
                )
            }
        }
    }

    func placeCursor(forText value: String, at position: Int = 0) {
        textField(forText: value)?.currentEditor()?.selectedRange = NSMakeRange(position, 0)
    }

    func textField(forText value: String) -> NSTextField? {
        noteWindow?.contentView?.getNestedSubviews().first(where: { $0.stringValue == value })
    }

    func minimizedFrame(for window: NSWindow) -> NSRect {
        let content = NSRect(origin: .zero, size: NSSize(width: Layout.minimizedNoteWidth, height: Layout.minimizedNoteHeight))
        let frame = window.frameRect(forContentRect: content)
        return NSRect(x: window.frame.minX, y: window.frame.maxY - frame.height, width: frame.width, height: frame.height)
    }

    func setColorPickerHidden(_ hidden: Bool) {
        guard let themeFrame = noteWindow?.contentView?.superview else { return }
        themeFrame.subviews
            .compactMap { $0 as? NoteColorPickerTitlebarControl }
            .forEach { $0.isHidden = hidden }
    }

    func setRestoreControlVisible(_ visible: Bool) {
        guard let themeFrame = noteWindow?.contentView?.superview else { return }
        let existing = themeFrame.subviews.compactMap { $0 as? MinimizedNoteRestoreTitlebarControl }
        guard visible else {
            existing.forEach { $0.removeFromSuperview() }
            return
        }
        guard existing.isEmpty,
              let picker = themeFrame.subviews.first(where: { $0 is NoteColorPickerTitlebarControl }) else {
            return
        }

        let restore = MinimizedNoteRestoreTitlebarControl { handleBringUp() }
        restore.frame = MacNoteTitlebarLayout.minimizedRestoreFrame(
            in: themeFrame.bounds,
            alignedWith: picker.frame
        )
        restore.autoresizingMask = [.minXMargin, .minYMargin]
        themeFrame.addSubview(restore, positioned: .above, relativeTo: nil)
    }
}
