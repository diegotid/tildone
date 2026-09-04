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
        noteWindow.ignoresMouseEvents = false
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
        let indentLevel = newTaskIndentLevel ?? 0
        newTaskText = ""
        newTaskIndentLevel = indentLevel
        Swift.Task {
            do {
                _ = try await store.addTask(
                    to: noteID,
                    text: text,
                    indentLevel: indentLevel
                )
            } catch {
                newTaskIndentLevel = nil
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error on task creation",
                    error: error
                )
            }
        }
    }

    func handleNewTaskTab(outdent: Bool) {
        adjustNewTaskDraftIndent(outdent: outdent)
        guard !newTaskText.isEmpty else { return }
        let text = newTaskText.capitalizingFirstLetter()
        let indentLevel = newTaskIndentLevel ?? 0
        newTaskText = ""
        focusedField = nil

        Swift.Task {
            do {
                let task = try await store.addTask(
                    to: noteID,
                    text: text,
                    indentLevel: indentLevel
                )
                focusTaskUsingKeyboard(task.id)
                newTaskIndentLevel = nil
            } catch {
                newTaskIndentLevel = nil
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error on task creation",
                    error: error
                )
            }
        }
    }

    func adjustNewTaskDraftIndent(outdent: Bool) {
        guard let precedingTask = tasks.last else { return }
        if outdent {
            newTaskIndentLevel = max(0, (newTaskIndentLevel ?? 0) - 1)
        } else {
            newTaskIndentLevel = min(
                (newTaskIndentLevel ?? 0) + 1,
                precedingTask.indentLevel + 1
            )
        }
    }

    func handleTaskEdit(_ task: TildoneDomain.Task, to text: String) {
        store.queueTaskTextEdit(
            task.id,
            text: text.capitalizingFirstLetter()
        ) { error in
            mutationErrorMessage = Self.mutationFailureMessage(
                operation: "Error on task edit",
                error: error
            )
        }
    }

    func handleTaskToggle(_ task: TildoneDomain.Task) {
        let originalOrderToken = CompletedTaskOrderPreference.originalOrderToken(for: task.id)
        let restoresOriginalPosition = originalOrderToken.map { $0 != task.orderToken } ?? false
        let animatesTaskMovement = moveCheckedTasksToEnd && (
            (!task.isCompleted && tasks.last?.id != task.id)
                || (task.isCompleted && restoresOriginalPosition)
        )
        if animatesTaskMovement {
            completedTaskMovementAnimationID = task.id
        }
        noteWindow?.makeFirstResponder(nil)
        Swift.Task {
            do {
                let movedParentID = try await store.setTaskCompletion(
                    task.id,
                    completed: !task.isCompleted,
                    moveToEndWhenCompleted: moveCheckedTasksToEnd
                )
                if let movedParentID {
                    collapsedTaskIDs.insert(movedParentID)
                }
        } catch {
                if animatesTaskMovement {
                    completedTaskMovementAnimationID = nil
                }
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error on task completion",
                    error: error
                )
            }
        }
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
        store.queueNoteTitleEdit(noteID, title: title) { error in
            mutationErrorMessage = Self.mutationFailureMessage(
                operation: "Error on topic edit",
                error: error
            )
        }
    }

    func handleKeyboard() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window == noteWindow else { return event }
            if (event.keyCode == Keyboard.arrowUp || event.keyCode == Keyboard.arrowDown),
               isEditingNativeTaskField() {
                return event
            }
            if event.keyCode == Keyboard.tabKey {
                // A held Tab key should not turn one deliberate hierarchy action into
                // several depth changes.
                guard !event.isARepeat else { return nil }
                let outdent = event.modifierFlags.contains(.shift)
                if focusedField == .newTask {
                    handleNewTaskTab(outdent: outdent)
                    return nil
                }
                if let taskID = activeFocusedTaskID {
                    // Inserted slots are deliberately empty, so their caret is
                    // necessarily at the trailing edge. Treat Tab as a hierarchy
                    // edit instead of moving focus away and causing the slot to be
                    // discarded.
                    if tasks.first(where: { $0.id == taskID })?.text.isEmpty == true {
                        handleTaskIndent(taskID, outdent: outdent)
                    } else if taskCaretIsAtTrailingEdge() {
                        outdent ? handleMoveUp(from: taskID) : handleMoveDown(from: taskID)
                    } else {
                        handleTaskIndent(taskID, outdent: outdent)
                    }
                    return nil
                }
            }
            if event.keyCode == Keyboard.returnKey,
               focusedField == .newTask,
               newTaskText.isEmpty,
               let newTaskIndentLevel,
               newTaskIndentLevel > 0 {
                self.newTaskIndentLevel = newTaskIndentLevel - 1
                return nil
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

    func taskCaretIsAtTrailingEdge() -> Bool {
        guard let editor = noteWindow?.firstResponder as? NSTextView else { return false }
        let selection = editor.selectedRange()
        return selection.length == 0
            && selection.location == (editor.string as NSString).length
    }

    func stopHandlingKeyboard() {
        guard let keyboardMonitor else { return }
        NSEvent.removeMonitor(keyboardMonitor)
        self.keyboardMonitor = nil
    }

    func isEditingNativeTaskField() -> Bool {
        guard let firstResponder = noteWindow?.firstResponder else { return false }
        return noteWindow?.contentView?.getNestedSubviews().contains { field in
            guard let taskField = field as? MouseSafeTaskNSTextField else { return false }
            return taskField.currentEditor() === firstResponder
        } ?? false
    }

    func handleTaskIndent(_ taskID: TaskID, outdent: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[index]
        if outdent {
            guard task.indentLevel > 0 else { return }
            let updates: [TaskStructureUpdate]
            do {
                updates = try store.stageTaskOutdent(taskID, in: noteID)
            } catch {
                mutationErrorMessage = Self.mutationFailureMessage(
                    operation: "Error changing task indentation",
                    error: error
                )
                return
            }
            guard !updates.isEmpty else { return }
            mutate(
                {
                    try await store.commitTaskStructureUpdates(
                        updates,
                        in: noteID,
                        moveCompletedGroupsToEnd: moveCheckedTasksToEnd,
                        undoDirection: .outdent
                    )
                },
                message: "Error changing task indentation"
            )
            return
        }

        guard index > 0 else { return }
        // Promote the hierarchy by exactly one level per Tab press. The preceding
        // row must be at this task's current depth (or deeper) to supply a valid
        // parent at the next level.
        guard tasks[index - 1].indentLevel >= task.indentLevel else { return }
        let delta = 1
        let updates = TaskHierarchy.subtreeRange(startingAt: index, in: tasks).map { offset in
            (id: tasks[offset].id, level: tasks[offset].indentLevel + delta)
        }
        let structureUpdates = store.stageTaskIndentLevels(updates, in: noteID)
        mutate(
            {
                try await store.commitTaskStructureUpdates(
                    structureUpdates,
                    in: noteID,
                    moveCompletedGroupsToEnd: moveCheckedTasksToEnd,
                    undoDirection: .indent
                )
            },
            message: "Error changing task indentation"
        )
    }

    func handleEnter(for task: TildoneDomain.Task, cursor: Int?) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let cursor = cursor ?? task.text.count
        let insertion = cursor == 0 ? index : index + 1
        insertEmptyTask(
            at: insertion,
            focusing: cursor == 0 ? task.id : nil,
            indentLevel: task.indentLevel
        )
    }

    func insertEmptyTask(
        at position: Int,
        focusing taskID: TaskID? = nil,
        indentLevel: Int? = nil
    ) {
        skipsNextTaskCountBottomScroll = true
        let emptyTaskIDs = Set(tasks.filter { !$0.isCompleted && $0.text.isEmpty }.map(\.id))
        let inheritedIndentLevel = indentLevel ?? (
            position < tasks.count ? tasks[position].indentLevel : tasks.last?.indentLevel ?? 0
        )
        let stagedTask: TildoneDomain.Task
        do {
            stagedTask = try store.stageEmptyTaskInsertion(
                in: noteID,
                at: position,
                deleting: emptyTaskIDs,
                indentLevel: inheritedIndentLevel
            )
        } catch {
            skipsNextTaskCountBottomScroll = false
            mutationErrorMessage = Self.mutationFailureMessage(
                operation: "Error on task creation",
                error: error
            )
            return
        }
        let requestedFocusID = taskID.flatMap { emptyTaskIDs.contains($0) ? nil : $0 }
        focusTaskUsingKeyboard(requestedFocusID ?? stagedTask.id)
        Swift.Task {
            do {
                try await store.commitStagedTaskInsertion(
                    stagedTask,
                    deleting: emptyTaskIDs
                )
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
        guard let clipboard = pastedText() else { return }
        let lines = clipboard.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        guard let first = lines.first, let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        mutate({
            try await store.editTask(task.id, text: first)
            for line in lines.dropFirst().reversed() {
                _ = try await store.addTask(
                    to: noteID,
                    text: line.capitalizingFirstLetter(),
                    insertingAt: index + 1,
                    indentLevel: task.indentLevel
                )
            }
        }, message: "Error pasting tasks")
    }

    func pasteIntoNewTask() {
        guard let clipboard = pastedText() else { return }
        newTaskText = clipboard
    }

    private func pastedText() -> String? {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string) {
            return text
        }
        if let text = pasteboard.string(forType: .URL) {
            return text
        }
        return (pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL)?.absoluteString
    }

    func handleBringUp() {
        guard let noteWindow, let restoration = minimizationState.beginRestoring() else { return }
        if noteWindow.title.starts(with: "_") {
            noteWindow.title = String(noteWindow.title.dropFirst())
        }
        setColorPickerHidden(false)
        setRestoreControlVisible(false)
        noteWindow.ignoresMouseEvents = NoteWindowClickThrough.shouldIgnoreMouseEvents(
            isEnabled: clickThroughNotes,
            isCommandPressed: NoteWindowClickThrough.isCommandPressed
        )
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
        if disappearing {
            if completionFadeBaseWindowAlpha == nil {
                completionFadeBaseWindowAlpha = noteWindow?.alphaValue
                    ?? NoteWindowOpacity.currentAlpha(for: noteID)
            }
            noteWindow?.alphaValue = completionFadeBaseWindowAlpha! * CGFloat(windowAlpha)
            noteWindow?.level = .floating
            if !didRaiseWindowForCompletionFade {
                noteWindow?.orderFront(nil)
                didRaiseWindowForCompletionFade = true
            }
        } else {
            if let baseAlpha = completionFadeBaseWindowAlpha {
                noteWindow?.alphaValue = baseAlpha
                completionFadeBaseWindowAlpha = nil
            }
            noteWindow?.level = .floating
            didRaiseWindowForCompletionFade = false
        }
        withAnimation {
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
        noteWindow.applyNoteBackgroundColor(
            color,
            alpha: tintAlpha
        )
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

    func handleNativeTaskBlur(_ taskID: TaskID) {
        if nativeFocusedTaskID == taskID { nativeFocusedTaskID = nil }
        if focusedTaskID == taskID { focusedTaskID = nil }

        // Give AppKit a turn to install a newly inserted row as first responder
        // before removing unfilled placeholders. This preserves Return-created
        // rows while still clearing an abandoned subtask slot.
        DispatchQueue.main.async {
            let preservedTaskID = activeFocusedTaskID.flatMap { focusedID in
                tasks.contains { $0.id == focusedID && $0.text.isEmpty } ? focusedID : nil
            }
            guard tasks.contains(where: {
                $0.text.isEmpty && $0.id != preservedTaskID
            }) else {
                return
            }
            skipsNextTaskCountBottomScroll = true
            mutate(
                {
                    try await store.cleanEmptyTasks(
                        in: noteID,
                        preserving: preservedTaskID
                    )
                },
                message: "Error cleaning note"
            )
        }
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
        skipsNextTaskCountBottomScroll = true
        mutate({ try await store.cleanEmptyTasks(in: noteID) }, message: "Error on task deletion")
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
        noteWindow?.noteTitlebarAccessoryController?.setColorPickerHidden(hidden)
    }

    func setRestoreControlVisible(_ visible: Bool) {
        noteWindow?.noteTitlebarAccessoryController?.setRestoreControlVisible(
            visible,
            foreground: minimizedForeground,
            onRestore: { handleBringUp() }
        )
    }

    func updateRestoreControlForeground() {
        noteWindow?.noteTitlebarAccessoryController?.setRestoreControlForeground(minimizedForeground)
    }
}
