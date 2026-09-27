import SwiftUI
import TildoneDomain

/// The same row and memo controls used in Mac notes, with constant bindings and
/// no-op actions. Never constructs a live Note, repository, or WindowAccessor.
struct MacProPreviewNote: View {
    let content: ProPreviewContent
    var noteColor: NoteColor = .yellow
    var backgroundOpacity = Double(NoteWindowBackground.defaultAlpha)
    @Environment(\.colorScheme) private var colorScheme

    private var foreground: Color {
        NoteContentForeground.color(colorScheme: colorScheme, backgroundOpacity: backgroundOpacity)
    }
    @FocusState private var focusedTaskID: TaskID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if content.note.kind == .singleTask, let task = content.tasks.first {
                MouseSafeTaskTextField(
                    richText: .constant(task.richText), taskID: task.id,
                    isFocused: false, placesCaretAtStartOnFocus: false,
                    fontSize: memoFontSize(for: task), textColor: foreground, cursorColor: foreground,
                    truncation: .multiple,
                    fontName: SingleMemoTypography.fontName(for: content.note.singleMemoFont),
                    alignment: .center,
                    lineHeightMultiple: SingleMemoTypography.lineHeightMultiple,
                    verticallyCentersContent: true,
                    onFocus: {}, onBlur: {}, onEnter: { _ in }, onMoveUp: {}, onMoveDown: {}
                )
            } else {
                Text(content.note.title ?? "")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                ForEach(Array(content.tasks.enumerated()), id: \.element.id) { index, task in
                    row(task, index: index)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .allowsHitTesting(false)
    }

    private func memoFontSize(for task: TildoneDomain.Task) -> CGFloat {
        let fontName = SingleMemoTypography.fontName(for: content.note.singleMemoFont)
        for size in stride(from: CGFloat(32), through: 14, by: -1) {
            let text = MouseSafeTaskTextField.attributedString(
                from: task.richText, fontSize: size, baseColor: NSColor(foreground),
                truncation: .multiple, fontName: fontName, alignment: .center,
                lineHeightMultiple: SingleMemoTypography.lineHeightMultiple
            )
            let storage = NSTextStorage(attributedString: text)
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: 188, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            if ceil(manager.usedRect(for: container).height) + size * 0.45 <= 234 { return size }
        }
        return 14
    }

    private func row(_ task: TildoneDomain.Task, index: Int) -> some View {
        TaskRow(
            task: task, dragPayload: MacTaskDragPayload(noteID: task.noteID, taskID: task.id),
            rowIndex: index, fontSize: 14,
            isDark: NoteContentForeground.usesLightText(colorScheme: colorScheme, backgroundOpacity: backgroundOpacity),
            noteBackgroundColor: Color(nsColor: noteColor.nsColor), noteBackgroundOpacity: backgroundOpacity,
            contentColor: foreground, cursorColor: foreground, searchQuery: "", placeholderColor: foreground,
            truncation: .multiple, isFirst: index == 0, followsDeeperTask: false,
            isShowingRowControls: false,
            hasSubtasks: TaskHierarchy.subtaskProgress(at: index, in: content.tasks) != nil,
            isSubtasksCollapsed: false,
            subtaskProgress: TaskHierarchy.subtaskProgress(at: index, in: content.tasks),
            checkboxChecked: task.isCompleted, isTaskCompletionPending: false,
            focusedTaskID: $focusedTaskID, isActive: false, placesCaretAtStartOnFocus: false,
            onNativeFocus: {}, onNativeBlur: {}, onEditLink: {}, onToggle: {},
            onEdit: { _ in }, onEnter: { _ in }, onCopy: {}, onPaste: {}, onPastedList: { _ in false },
            onMoveUp: {}, onSubmit: {}, onInsertAbove: {}, onToggleSubtasks: {},
            onIndent: {}, onOutdent: {}, onDrop: { _, _ in false }, onHover: { _ in }, onRowHover: { _ in }
        )
    }
}


extension MacProPreviewNote {
    @MainActor
    static func rasterImage(content: ProPreviewContent, locale: Locale, colorScheme: ColorScheme = .light,
                            backgroundOpacity: Double = Double(NoteWindowBackground.defaultAlpha),
                            noteColor: NoteColor = .yellow) -> NSImage? {
        let view = MacProPreviewNote(content: content, noteColor: noteColor, backgroundOpacity: backgroundOpacity)
            .environment(\.locale, locale)
            .environment(\.colorScheme, colorScheme)
            .frame(width: 216, height: 262)
        return capture(view, size: CGSize(width: 216, height: 262), colorScheme: colorScheme)
    }

    @MainActor
    static func backgroundRasterImage(noteColor: NoteColor, backgroundOpacity: Double,
                                      colorScheme: ColorScheme) -> NSImage? {
        capture(MacProPreviewNoteBackground(noteColor: noteColor, backgroundOpacity: backgroundOpacity)
                    .environment(\.colorScheme, colorScheme),
                size: CGSize(width: 216, height: 288), colorScheme: colorScheme)
    }

    @MainActor
    private static func capture<Content: View>(_ view: Content, size: CGSize, colorScheme: ColorScheme) -> NSImage? {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        defer { window.close() }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}

/// Matches the material and tint used by the Settings note previews.
struct MacProPreviewNoteBackground: View {
    let noteColor: NoteColor
    let backgroundOpacity: Double

    var body: some View {
        ZStack {
            VisualEffectBlurView(material: .hudWindow, blendingMode: .withinWindow)
                .allowsHitTesting(false)
            Color(nsColor: noteColor.nsColor).opacity(backgroundOpacity)
        }
    }
}
