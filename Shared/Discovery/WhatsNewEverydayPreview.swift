import SwiftUI
import TildoneDomain

struct WhatsNewEverydayPreview: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    @AppStorage(NoteColor.storageKey) private var noteColorRawValue = NoteColor.yellow.legacyRawValue
    @AppStorage(NoteWindowBackground.opacityStorageKey) private var opacity = Double(NoteWindowBackground.defaultAlpha)
    @AppStorage(AppAppearance.moveCheckedTasksToEndStorageKey) private var movesCompletedTasksToEnd = false
    @AppStorage(FontSize.storageKey) private var fontSize = Double(FontSize.small.rawValue)
    @AppStorage(TaskLineTruncation.storageKey) private var truncation: TaskLineTruncation = .single
    @State private var image: NSImage?

    private var noteColor: NoteColor { NoteColor(legacyRawValue: noteColorRawValue) ?? .yellow }
    #else
    @FocusState private var previewFocusedTask: TaskID?
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            ZStack {
                SettingsPreviewBackground(size: CGSize(width: 360, height: 360))
                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            Circle().fill(index == 1 ? Color.yellow : .gray.opacity(0.4))
                                .frame(width: 12, height: 12)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 11).frame(height: 26)
                    if let image { Image(nsImage: image).resizable().frame(width: 216, height: 262) }
                    else { Color.clear.frame(width: 216, height: 262) }
                }
                .frame(width: 216, height: 288)
                .background(MacProPreviewNoteBackground(noteColor: noteColor, backgroundOpacity: opacity))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
            }
            .frame(width: 360, height: 360)
            .scaleEffect(0.85)
            .frame(width: 306, height: 306)
            .task(id: "\(locale.identifier)-\(colorScheme)-\(noteColorRawValue)-\(opacity)-\(fontSize)-\(truncation.rawValue)-\(movesCompletedTasksToEnd)") {
                image = MacProPreviewNote.rasterImage(
                    content: WhatsNewPreviewContent(noteColor: noteColor, movesCompletedTasksToEnd: movesCompletedTasksToEnd, locale: locale).content,
                    locale: locale, colorScheme: colorScheme, backgroundOpacity: opacity,
                    noteColor: noteColor, fontSize: fontSize, truncation: truncation
                )
            }
            #else
            let content = WhatsNewPreviewContent(noteColor: .yellow, movesCompletedTasksToEnd: false, locale: locale).content
            ZStack {
                (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
                iOSNote(content)
            }
            .frame(maxWidth: .infinity, minHeight: 340)
            #endif
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    #if os(iOS)
    private func iOSNote(_ content: ProPreviewContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(content.note.title ?? "").font(.headline)
                Spacer(minLength: 8)
                NoteCompletionGauge(
                    summary: NoteTaskSummary(noteID: content.note.id, tasks: content.tasks),
                    labelColor: .black
                )
                .frame(width: 30, height: 30)
            }
            ForEach(content.tasks, id: \.id) { task in
                TaskRow(
                    task: task, noteColor: content.note.color, subtaskProgress: nil,
                    subtasksExpanded: nil, canIndent: false, canOutdent: false,
                    focusedTask: $previewFocusedTask,
                    onBeginEditing: {}, onCommit: { _ in }, onSubmit: {}, onToggle: {},
                    onToggleSubtasks: {}, onIndent: {}, onOutdent: {}, onMoveUp: {}, onMoveDown: {}
                )
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 264, height: 288, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(content.note.color.swiftUIColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        .environment(\.colorScheme, .light)
    }
    #endif
}
