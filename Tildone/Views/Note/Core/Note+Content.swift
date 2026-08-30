//
//  Note+Content.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

extension Note {
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
                        .onReceive(NotificationCenter.default.publisher(for: .minimizeAll)) { _ in handleMinimize() }
                    }
                    .onChange(of: focusedTaskID) { _, taskID in
                        if taskID != keyboardFocusedTaskID {
                            keyboardFocusedTaskID = nil
                        }
                        guard let taskID else { return }
                        withAnimation {
                            scroll.scrollTo(taskID, anchor: .center)
                        }
                    }
                    .modifier(ScrollFrame())
                    .onChange(of: tasks.count) { _, _ in
                        guard !skipsNextTaskCountBottomScroll else {
                            skipsNextTaskCountBottomScroll = false
                            return
                        }
                        withAnimation { scroll.scrollTo(Id.bottomAnchor, anchor: .bottom) }
                    }
                }
                if isTopScrolledOut { scrollingHeader() }
            }
            .blur(radius: isContentBlurred ? 3 : 0)
            .opacity(windowAlpha / (isDone ? 2 : 1))
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
        let total = note.tasks.count
        let complete = pending == 0 && total > 0
        let foreground = minimizedForeground
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .bottomLeading) {
                Gauge(value: total == 0 ? 0 : Float(total - pending), in: 0...Float(max(total, 1))) {
                    EmptyView()
                } currentValueLabel: {
                    if complete {
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
                .gaugeStyle(.accessoryCircular).tint(Gradient(colors: [.clear, foreground]))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(statusText(complete: complete, total: total))
                    .font(.system(size: 10))
                    .foregroundStyle(foreground)
                    .padding(.leading, 13)
                    .padding(.bottom, 13)
                    .frame(maxWidth: 54, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, -14)
            .padding(.horizontal, 8)
            .opacity(isHoveringMinimizedTaskList ? 0 : 1)

            minimizedTaskPreview(note, foreground: foreground)
                .opacity(isHoveringMinimizedTaskList ? 1 : 0)
                .allowsHitTesting(false)

            if let title = note.title {
                Text(title).font(.system(size: 12)).foregroundStyle(foreground).bold().lineLimit(1)
                    .truncationMode(.tail)
                    .frame(
                        width: Layout.minimizedNoteWidth - 10 - MacNoteTitlebarLayout.minimizedRestoreWidth,
                        alignment: .leading
                    )
                    .padding(.top, -26)
                    .padding(.leading, 8)
            }
        }
        .frame(width: Layout.minimizedNoteWidth, height: Layout.minimizedNoteHeight)
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
        .padding(.top, -3)
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
                .font(.system(size: 12))
                .foregroundStyle(foreground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusText(complete: Bool, total: Int) -> String {
        if complete { return String(localized: "all done") }
        if total == 0 { return String(localized: "no tasks") }
        return String(localized: "pending")
    }

    func listTopic() -> some View {
        let size = 20 / CGFloat(FontSize.small.rawValue) * CGFloat(fontSize)
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
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, MacNoteTitlebarLayout.titleLeadingInset)
                    .padding(.trailing, MacNoteTitlebarLayout.titleTrailingInset)
                    .offset(y: -1)
                }
            }
            Spacer()
        }.padding(.top, -30)
    }

    func newListItem() -> some View {
        HStack(spacing: 8) {
            Checkbox(size: max(10, CGFloat(fontSize) + 1)).disabled(true)
            ZStack(alignment: .leading) {
                if newTaskText.isEmpty { Text("New task").font(.system(size: CGFloat(fontSize))).foregroundColor(minimizedForeground).opacity(0.35).allowsHitTesting(false) }
                TextField("", text: $newTaskText).textFieldStyle(.plain).font(.system(size: CGFloat(fontSize))).foregroundColor(noteForeground).tint(noteForeground)
                    .onSubmit { handleNewTaskCommit() }.focused($focusedField, equals: .newTask)
                    .onChange(of: focusedField) { _, field in if field != .newTask && !newTaskText.isEmpty { handleNewTaskCommit() } }
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in handleNewTaskCommit() }
            }
            Spacer()
        }
        .padding(.leading, 2)
        .padding(.bottom, 10)
        .allowsHitTesting(!isInsertedNewTaskFocused)
    }

    func topicListItem() -> some View {
        listTopic()
            .opacity(isTopScrolledOut || isTopicHidden ? 0 : 1)
            .frame(height: isTopicHidden ? 1 : 30)
            .padding(.bottom, CGFloat(fontSize - 10))
    }

    func taskRow(_ task: TildoneDomain.Task, at index: Int) -> TaskRow {
        TaskRow(
            task: task,
            dragPayload: MacTaskDragPayload(noteID: noteID, taskID: task.id),
            rowIndex: index,
            fontSize: fontSize,
            isDark: isDark,
            contentColor: noteForeground,
            cursorColor: noteForeground,
            placeholderColor: minimizedForeground,
            truncation: taskLineTruncation,
            isFirst: task.id == tasks.first?.id,
            isShowingRowControls: hoveredTaskID == task.id,
            hasSubtasks: TaskHierarchy.hasSubtasks(at: index, in: tasks),
            isSubtasksCollapsed: collapsedTaskIDs.contains(task.id),
            subtaskProgress: TaskHierarchy.subtaskProgress(at: index, in: tasks),
            feedbackResetToken: taskDropFeedbackResetToken,
            focusedTaskID: $focusedTaskID,
            isActive: activeFocusedTaskID == task.id,
            placesCaretAtStartOnFocus: keyboardFocusedTaskID == task.id,
            onNativeFocus: { activateNativeTask(task.id) },
            onNativeBlur: { handleNativeTaskBlur(task.id) },
            onToggle: { handleTaskToggle(task) },
            onEdit: { handleTaskEdit(task, to: $0) },
            onEnter: { handleEnter(for: task) },
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
        }.opacity(windowAlpha * 0.9)
    }
}
