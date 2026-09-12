//
//  Note+Content.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

extension Note {
    func singleTaskNote(_ note: MacNoteSnapshot) -> some View {
        ZStack {
            GeometryReader { geometry in
                if let task = note.singleTask {
                    let fontName = SingleMemoTypography.fontName(for: note.singleMemoFont)
                    let liveRichText = singleTaskDraftID == task.id
                        ? singleTaskDraft
                        : task.richText
                    let size = singleTaskFontSize(
                        text: liveRichText.text,
                        fontName: fontName,
                        availableSize: CGSize(
                            width: max(1, geometry.size.width - 12),
                            height: max(1, geometry.size.height - 8)
                        )
                    )
                    MouseSafeTaskTextField(
                        richText: Binding(
                            get: { liveRichText },
                            set: { value in
                                let value = value.capitalizingFirstLetter()
                                singleTaskDraftID = task.id
                                singleTaskDraft = value
                                handleTaskEdit(task, to: value)
                            }
                        ),
                        taskID: task.id,
                        isFocused: activeFocusedTaskID == task.id,
                        placesCaretAtStartOnFocus: keyboardFocusedTaskID == task.id,
                        fontSize: size,
                        textColor: noteForeground,
                        cursorColor: noteForeground,
                        truncation: .multiple,
                        fontName: fontName,
                        alignment: .center,
                        lineHeightMultiple: SingleMemoTypography.lineHeightMultiple,
                        verticallyCentersContent: true,
                        onFocus: {
                            activateNativeTask(task.id)
                            keyboardFocusedTaskID = nil
                        },
                        onBlur: { handleNativeTaskBlur(task.id) },
                        onEnter: { _ in },
                        onMoveUp: {},
                        onMoveDown: {}
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .strikethrough(task.isCompleted, color: .accentColor)
                    .opacity(task.isCompleted ? 0.6 : 1)
                    .onAppear {
                        singleTaskDraftID = task.id
                        singleTaskDraft = task.richText
                    }
                    .onChange(of: task.richText) { _, value in
                        guard activeFocusedTaskID != task.id else { return }
                        singleTaskDraftID = task.id
                        singleTaskDraft = value
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .blur(radius: isContentBlurred ? 3 : 0)
            if isDone { doneOverlay() }
        }
        .frame(minWidth: Layout.minNoteWidth, idealWidth: Layout.defaultNoteWidth, maxWidth: .infinity,
               minHeight: Layout.minNoteHeight, idealHeight: Layout.defaultNoteHeight, maxHeight: .infinity)
        .background(WindowAccessor(note: self, window: $noteWindow))
        .onAppear {
            handleKeyboard()
            if let task = note.singleTask { focusTaskUsingKeyboard(task.id) }
        }
        .onDisappear { stopHandlingKeyboard() }
        .onChange(of: note.isDeletable) { _, _ in updateWindowClosability() }
        .onReceive(NotificationCenter.default.publisher(for: .minimizeAll)) { _ in handleMinimize() }
        .onReceive(NotificationCenter.default.publisher(for: .visibility)) { notification in
            if let (blur, normal) = notification.object as? (Bool, Bool) {
                noteWindow?.level = normal ? .normal : .floating
                isTextBlurred = blur
            }
        }
        .disabled(isContentBlurred)
        .onHover { isPointerHovering = $0 }
    }

    private func singleTaskFontSize(
        text: String,
        fontName: String,
        availableSize: CGSize
    ) -> CGFloat {
        guard !text.isEmpty else { return min(72, availableSize.height * 0.4) }
        var low: CGFloat = 18
        var high: CGFloat = 128
        for _ in 0..<8 {
            let candidate = (low + high) / 2
            let attributed = MouseSafeTaskTextField.attributedString(
                from: RichText(text: text),
                fontSize: candidate,
                baseColor: .textColor,
                truncation: .multiple,
                fontName: fontName,
                alignment: .center,
                lineHeightMultiple: SingleMemoTypography.lineHeightMultiple
            )
            let bounds = attributed.boundingRect(
                with: NSSize(width: availableSize.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            // TextKit's field editor adds line-fragment and insertion-point
            // slack beyond NSString's glyph bounds. Reserve part of a line so
            // the next wrapped word can never peek outside the fitted block.
            let safeHeight = ceil(bounds.height) + candidate * 0.45
            if safeHeight <= availableSize.height { low = candidate } else { high = candidate }
        }
        return low * 0.6
    }

    func taskList(_ note: MacNoteSnapshot) -> some View {
        ZStack {
            Group {
                ScrollViewReader { scroll in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            topicListItem()
                            taskDropTarget(at: 0)
                            ForEach(visibleTaskEntries, id: \.task.id) { entry in
                                taskRow(entry.task, at: entry.index)
                                    .id(entry.task.id)
                                taskDropTarget(at: entry.index + 1)
                            }
                            newListItem().opacity(isDone || isContentBlurred || isInsertedNewTaskFocused ? 0 : 1)
                            Spacer().id(Id.bottomAnchor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(
                            completedTaskMovementAnimationID == nil
                                ? nil
                                : .linear(duration: 0.35),
                            value: tasks.map(\.id)
                        )
                        .onChange(of: tasks.map(\.id)) { _, _ in
                            guard let taskID = completedTaskMovementAnimationID else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                guard completedTaskMovementAnimationID == taskID else { return }
                                completedTaskMovementAnimationID = nil
                            }
                        }
                        .onAppear {
                            if note.title == nil { focusOnTopic() } else { focusOnNewTask() }
                            applyInitialFocusIfNeeded()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                            guard focusedField == .newTask else { return }
                            pasteIntoNewTask()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .minimizeAll)) { _ in handleMinimize() }
                    }
                    .onChange(of: focusedTaskID) { _, taskID in
                        if taskID != keyboardFocusedTaskID {
                            keyboardFocusedTaskID = nil
                        }
                        guard let taskID else { return }
                        scrollToTaskAfterLayout(taskID, using: scroll)
                    }
                    .modifier(ScrollFrame())
                    .onChange(of: tasks.count) { _, _ in
                        guard !skipsNextTaskCountBottomScroll else {
                            skipsNextTaskCountBottomScroll = false
                            return
                        }
                        scrollToBottomAfterLayout(using: scroll)
                    }
                }
                if isTopScrolledOut { scrollingHeader() }
            }
            .blur(radius: isContentBlurred ? 3 : 0)
            .opacity(1)
            .animation(
                .easeInOut(duration: NoteWindowClickThrough.visualTransitionDuration),
                value: isContentBlurred
            )
            if isDone { doneOverlay() }
        }
        .frame(minWidth: Layout.minNoteWidth, idealWidth: Layout.defaultNoteWidth, maxWidth: .infinity,
               minHeight: Layout.minNoteHeight, idealHeight: Layout.defaultNoteHeight, maxHeight: .infinity)
        .background(WindowAccessor(note: self, window: $noteWindow))
        .onAppear {
            handleKeyboard()
            convertLegacyFontSizeSettingIfNeeded()
            applyInitialFocusIfNeeded()
        }
        .onDisappear {
            stopHandlingKeyboard()
        }
        .onChange(of: noteWindow) { _, _ in
            applyInitialFocusIfNeeded()
            if completionFade.isFading {
                advanceCompletionFade(Date())
            } else {
                updateFadeAppearance()
            }
        }
        .onChange(of: note.isDeletable) { _, _ in updateWindowClosability() }
        .onReceive(NotificationCenter.default.publisher(for: .visibility)) { notification in
            if let (blur, normal) = notification.object as? (Bool, Bool) {
                noteWindow?.level = normal ? .normal : .floating
                isTextBlurred = blur
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clean), perform: cleanIfRequested)
        .onReceive(NotificationCenter.default.publisher(for: .noteWindowClickThroughCommandChanged)) { notification in
            guard let (interactingNoteID, isInteracting) = notification.object as? (NoteID, Bool),
                  interactingNoteID == noteID else {
                return
            }
            isClickThroughCommandInteractionActive = isInteracting
        }
        .onChange(of: clickThroughNotes) { _, isEnabled in
            guard !isEnabled else { return }
            isPointerHovering = noteWindow?.frame.contains(NSEvent.mouseLocation) ?? false
        }
        .disabled(isContentBlurred)
        .onHover { isPointerHovering = $0 }
    }

    func taskListProgress(_ note: MacNoteSnapshot) -> some View {
        let pending = note.pendingTasks.count
        let total = note.progressTasks.count
        let foreground = minimizedForeground
        let compactSize = CompactNoteScale.contentSize(for: CGFloat(compactNoteScale))
        return ZStack(alignment: .topLeading) {
            if note.kind == .singleTask {
                Text(note.singleTask?.text ?? "")
                    .font(.custom(
                        SingleMemoTypography.fontName(for: note.singleMemoFont),
                        size: 16
                    ))
                    .lineSpacing(SingleMemoTypography.lineSpacing(for: 16))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                    .strikethrough(note.singleTask?.isCompleted == true)
                    .foregroundStyle(foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(8)
            } else {
                CompactNotePresentation(
                    pending: pending,
                    total: total,
                    title: note.title,
                    foreground: foreground,
                    summaryOpacity: isHoveringMinimizedTaskList ? 0 : 1,
                    titleWidth: Layout.minimizedNoteWidth
                        - 10
                        - MacNoteTitlebarLayout.minimizedRestoreWidth
                )
                minimizedTaskPreview(note, foreground: foreground)
                    .opacity(isHoveringMinimizedTaskList ? 1 : 0)
                    .allowsHitTesting(false)
            }

            Image("MaximizeIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 10, height: 10)
                .foregroundStyle(foreground)
                .padding(.top, 6)
                .padding(.trailing, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
        }
        .frame(width: Layout.minimizedNoteWidth, height: Layout.minimizedNoteHeight)
        .scaleEffect(CGFloat(compactNoteScale), anchor: .topLeading)
        .frame(
            width: compactSize.width,
            height: compactSize.height,
            alignment: .topLeading
        )
        .animation(.easeInOut(duration: 0.2), value: isHoveringMinimizedTaskList)
        .background(WindowAccessor(note: self, window: $noteWindow))
        .onHover { isHoveringMinimizedTaskList = $0 }
        .onTapGesture(perform: handleBringUp)
        .onReceive(NotificationCenter.default.publisher(for: .bringAllUp)) { _ in handleBringUp() }
    }

    private func minimizedTaskPreview(_ note: MacNoteSnapshot, foreground: Color) -> some View {
        let pendingTasks = note.pendingTasks
        let maximumLines = taskLineTruncation == .multiple ? 2 : 1
        return GeometryReader { geometry in
            ViewThatFits(in: .vertical) {
                minimizedTaskRows(Array(pendingTasks.prefix(6)), foreground: foreground, maximumLines: maximumLines)
                minimizedTaskRows(Array(pendingTasks.prefix(5)), foreground: foreground, maximumLines: maximumLines)
                minimizedTaskRows(Array(pendingTasks.prefix(4)), foreground: foreground, maximumLines: maximumLines)
                minimizedTaskRows(Array(pendingTasks.prefix(3)), foreground: foreground, maximumLines: maximumLines)
                minimizedTaskRows(Array(pendingTasks.prefix(2)), foreground: foreground, maximumLines: maximumLines)
                minimizedTaskRows(Array(pendingTasks.prefix(1)), foreground: foreground, maximumLines: maximumLines)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .opacity(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.top, 28)
        .clipped()
    }

    private func minimizedTaskRows(
        _ tasks: [TildoneDomain.Task],
        foreground: Color,
        maximumLines: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tasks, id: \.id) { task in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "•")
                        .accessibilityHidden(true)
                    Text(task.text)
                        .lineLimit(maximumLines)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11))
                .foregroundStyle(foreground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func listTopic() -> some View {
        let size = NoteTypography.topicFontSize(for: CGFloat(fontSize))
        return GeometryReader { geometry in
            TextField("Topic", text: Binding(get: { note?.title ?? "" }, set: handleTopicEdit))
                .textFieldStyle(.plain).truncationMode(.tail).font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundColor(noteForeground).background(Color.clear).padding(.top, 5)
                .tint(noteForeground)
                .focused($focusedField, equals: .topic)
                .onChange(of: focusedField) { _, field in
                    if let title = note?.title, field == .topic { placeCursor(forText: title) }
                    updateTopicVisibility()
                }
                .onSubmit { tasks.isEmpty ? focusOnNewTask() : handleMoveDown() }
                .onChange(of: geometry.frame(in: .global)) { _, frame in withAnimation(.easeInOut) { isTopScrolledOut = frame.minY < 10 } }
                .onHover { hovering in if hovering { isTopicHidden = false } else { updateTopicVisibility() } }
        }
        .padding(.bottom, size)
    }

    func scrollingHeader() -> some View {
        VStack {
            ZStack {
                Color.clear
                    .frame(height: 30)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.black.opacity(0.2)).frame(height: 1)
                    }
                if let title = note?.title {
                    HStack(spacing: 0) {
                        Text(title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(noteForeground)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, MacNoteTitlebarLayout.titleLeadingInset)
                    .padding(.trailing, MacNoteTitlebarLayout.titleTrailingInset(
                        showsSingleTaskCheckbox: noteKind == .singleTask
                    ))
                    .offset(y: -1.5)
                }
            }
            Spacer()
        }.padding(.top, -30)
    }

    func newListItem() -> some View {
        let taskControlSize = NoteTypography.taskControlSize(for: CGFloat(fontSize))
        let taskLineHeight = NoteTypography.taskLineHeight(for: CGFloat(fontSize))
        let taskControlVerticalPadding = max(0, (taskLineHeight - taskControlSize) / 2)

        return HStack(alignment: .top, spacing: 8) {
            Checkbox(size: taskControlSize)
                .disabled(true)
                .padding(.vertical, taskControlVerticalPadding)
            ZStack(alignment: .leading) {
                if newTaskText.isEmpty { Text("New task").font(.system(size: CGFloat(fontSize))).foregroundColor(minimizedForeground).opacity(0.35).allowsHitTesting(false) }
                TextField("", text: $newTaskText).textFieldStyle(.plain).font(.system(size: CGFloat(fontSize))).foregroundColor(noteForeground).tint(noteForeground)
                    .onSubmit { handleNewTaskCommit() }.focused($focusedField, equals: .newTask)
                    .onChange(of: focusedField) { _, field in
                        guard field != .newTask else { return }
                        if newTaskText.isEmpty {
                            newTaskIndentLevel = nil
                        } else {
                            handleNewTaskCommit()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in handleNewTaskCommit() }
            }
            .frame(maxWidth: .infinity, minHeight: taskLineHeight, alignment: .leading)
            Spacer()
        }
        .padding(.leading, 2 + CGFloat(newTaskIndentLevel ?? 0) * (Layout.checkboxSize + 8))
        .padding(.bottom, 10)
        .allowsHitTesting(!isInsertedNewTaskFocused)
    }

    func topicListItem() -> some View {
        let taskFontSize = CGFloat(fontSize)
        return listTopic()
            .opacity(isTopScrolledOut || isTopicHidden ? 0 : 1)
            .frame(height: isTopicHidden ? 1 : NoteTypography.topicRowHeight(for: taskFontSize))
            .padding(.bottom, max(0, taskFontSize - 10))
    }

    func taskRow(_ task: TildoneDomain.Task, at index: Int) -> TaskRow {
        TaskRow(
            task: task,
            dragPayload: MacTaskDragPayload(noteID: noteID, taskID: task.id),
            rowIndex: index,
            fontSize: fontSize,
            isDark: isDark,
            noteBackgroundColor: Color(nsColor: noteColor.nsColor),
            contentColor: noteForeground,
            cursorColor: noteForeground,
            placeholderColor: minimizedForeground,
            truncation: taskLineTruncation,
            isFirst: task.id == tasks.first?.id,
            followsDeeperTask: followsVisibleDeeperTask(at: index),
            isShowingRowControls: hoveredTaskID == task.id,
            hasSubtasks: TaskHierarchy.hasSubtasks(at: index, in: tasks),
            isSubtasksCollapsed: collapsedTaskIDs.contains(task.id),
            subtaskProgress: TaskHierarchy.subtaskProgress(at: index, in: tasks),
            checkboxChecked: optimisticTaskCompletions[task.id] ?? task.isCompleted,
            isTaskCompletionPending: optimisticTaskCompletions[task.id] != nil,
            feedbackResetToken: taskDropFeedbackResetToken,
            focusedTaskID: $focusedTaskID,
            isActive: activeFocusedTaskID == task.id,
            placesCaretAtStartOnFocus: keyboardFocusedTaskID == task.id,
            onNativeFocus: { activateNativeTask(task.id) },
            onNativeBlur: { handleNativeTaskBlur(task.id) },
            onEditLink: { focusTaskUsingKeyboard(task.id) },
            onToggle: { handleTaskToggle(task) },
            onEdit: { handleTaskEdit(task, to: $0) },
            onEnter: { handleEnter(for: task, cursor: $0) },
            onCopy: { Copier.copy(task.text, forType: .string) },
            onPaste: { paste(into: task) },
            onMoveUp: { handleMoveUp(from: task.id) },
            onSubmit: { handleMoveDown(from: task.id) },
            onInsertAbove: { insertEmptyTask(at: index, indentLevel: task.indentLevel) },
            onToggleSubtasks: {
                if collapsedTaskIDs.contains(task.id) {
                    collapsedTaskIDs.remove(task.id)
                } else {
                    collapsedTaskIDs.insert(task.id)
                }
            },
            onIndent: { handleTaskIndent(task.id, outdent: false) },
            onOutdent: { handleTaskIndent(task.id, outdent: true) },
            onDrop: { payload, destination in
                handleTaskDrop(payload, at: destination)
            },
            onHover: { hovering in
                if hovering { isTopicHidden = false } else { updateTopicVisibility() }
            },
            onRowHover: { hovering in
                if hovering {
                    hoveredTaskID = task.id
                } else if hoveredTaskID == task.id {
                    hoveredTaskID = nil
                }
            }
        )
    }

    /// Only an expanded top-level parent creates the extra separation after
    /// its visible children. Collapsed and nested parents retain regular line
    /// spacing before the next visible sibling.
    func followsVisibleDeeperTask(at index: Int) -> Bool {
        guard index > 0, tasks[index].indentLevel < tasks[index - 1].indentLevel else {
            return false
        }

        for previousIndex in stride(from: index - 1, through: 0, by: -1) {
            let previousTask = tasks[previousIndex]
            guard previousTask.indentLevel <= tasks[index].indentLevel else { continue }
            return previousTask.indentLevel == 0 && !collapsedTaskIDs.contains(previousTask.id)
        }

        return true
    }

    /// A task inserted from an active field is published before SwiftUI has
    /// laid out its new row. Scrolling on the next run-loop turn makes the
    /// scroll view use that row's real frame, keeping the caret inside the
    /// note rather than below its bottom edge.
    func scrollToTaskAfterLayout(_ taskID: TaskID, using scroll: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation {
                scroll.scrollTo(taskID, anchor: .center)
            }
        }
    }

    func scrollToBottomAfterLayout(using scroll: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation {
                scroll.scrollTo(Id.bottomAnchor, anchor: .bottom)
            }
        }
    }

    func taskDropTarget(at destination: Int) -> TaskReorderDropTarget {
        TaskReorderDropTarget(feedbackResetToken: taskDropFeedbackResetToken) { payload in
            handleTaskDrop(payload, at: destination)
        }
    }

    func doneOverlay() -> some View {
        VStack {
            Spacer()
            Image(systemName: "checkmark").padding(.top, 12).padding(.leading, 12).font(.system(size: 90, weight: .bold)).foregroundColor(.accentColor).symbolEffect(.bounce, value: completionFade.isFading)
            Text("Done!").padding(.leading, 6).padding(.bottom, completionFade.isFading ? 30 : 60).font(.system(size: 30, weight: .bold)).foregroundColor(.accentColor)
            Spacer()
            if completionFade.isFading {
                ZStack {
                    ProgressView("Fading out...", value: fadeAwayProgress, total: Timeout.noteFadeOutSeconds).foregroundColor(.accentColor).padding(.horizontal, 20).padding(.bottom, 12)
                    HStack {
                        Spacer()
                        Button("Cancel", action: cancelCompletionFade)
                            .buttonStyle(.plain)
                            .foregroundStyle(minimizedForeground)
                            .padding(.trailing, 20)
                            .padding(.bottom, 30)
                    }
                }
            }
        }.opacity(0.9)
    }
}

struct MinimizedNoteSummary: View {
    let pending: Int
    let total: Int
    let foreground: Color

    private var isComplete: Bool { pending == 0 && total > 0 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Gauge(value: total == 0 ? 0 : Float(total - pending), in: 0...Float(max(total, 1))) {
                EmptyView()
            } currentValueLabel: {
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(foreground)
                        .offset(y: -2)
                } else {
                    Text("\(pending)")
                        .bold()
                        .font(.system(size: pending > 9 ? 24 : 30))
                        .foregroundStyle(foreground)
                        .padding(.top, -2)
                }
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.clear, foreground]))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(foreground)
                .padding(.leading, 13)
                .padding(.bottom, 13)
                .frame(maxWidth: 54, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.top, 20)
        .padding(.horizontal, 8)
    }

    private var statusText: String {
        if isComplete { return String(localized: "all done") }
        if total == 0 { return String(localized: "no tasks") }
        return String(localized: "pending")
    }
}

struct CompactNotePresentation: View {
    let pending: Int
    let total: Int
    let title: String?
    let foreground: Color
    var summaryOpacity = 1.0
    var titleWidth = Layout.minimizedNoteWidth - 16

    var body: some View {
        ZStack(alignment: .topLeading) {
            MinimizedNoteSummary(
                pending: pending,
                total: total,
                foreground: foreground
            )
            .opacity(summaryOpacity)

            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: titleWidth, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.leading, 8)
            }
        }
    }
}
