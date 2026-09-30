import SwiftUI
import TildoneDomain

struct CompanionPreview: View {
    var showsPhone = true
    @Environment(\.locale) private var locale

    private var yellowContent: ProPreviewContent {
        ProPreviewContent(feature: .gathering, locale: locale, noteColor: .yellow)
    }

    private var blueContent: ProPreviewContent {
        ProPreviewContent(feature: .singleMemo, locale: locale, noteColor: .blue)
    }

    var body: some View {
        #if os(macOS)
        devicePreview
        #else
        devicePreview
        #endif
    }

    private var devicePreview: some View {
        ZStack {
            desktopBezel
                .offset(x: showsPhone ? -118 : 0, y: 18)
            if showsPhone {
                Image(systemName: "icloud")
                    .font(.system(size: 33, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .offset(x: 96, y: -2)
                phoneBezel
                    .scaleEffect(0.9)
                    .frame(width: 148, height: 263)
                    .offset(x: 203, y: 0)
            }
        }
        .frame(width: 580, height: 320)
        .accessibilityHidden(true)
    }

    private var desktopBezel: some View {
        VStack(spacing: 0) {
            ZStack {
                #if os(macOS)
                SettingsPreviewBackground(size: CGSize(width: 340, height: 220))
                HStack(spacing: 10) {
                    macNote(yellowContent, color: .yellow)
                    macNote(blueContent, color: .blue)
                }
                #else
                ZStack {
                    Color(red: 0.18, green: 0.22, blue: 0.26)
                    HStack(spacing: 10) {
                        desktopNote(yellowContent, color: .yellow)
                        desktopNote(blueContent, color: .blue)
                    }
                }
                #endif
            }
            .frame(width: 340, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(7)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.24), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.20)).frame(width: 32, height: 24)
            Capsule().fill(Color(white: 0.25)).frame(width: 112, height: 6)
                .padding(.top, 1)
        }
        .frame(width: 356, height: 265)
    }

    private var phoneBezel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 29, style: .continuous).fill(Color(white: 0.07))
            VStack(spacing: 7) {
                Capsule().fill(.white.opacity(0.20)).frame(width: 43, height: 4).padding(.top, 7)
                ZStack {
                    phoneCard(yellowContent, color: .yellow)
                        .rotationEffect(.degrees(-5))
                        .offset(x: -9, y: -5)
                    phoneCard(blueContent, color: .blue)
                        .rotationEffect(.degrees(4))
                        .offset(x: 9, y: 8)
                }
                .frame(maxHeight: .infinity)
                Capsule().fill(.white.opacity(0.66)).frame(width: 48, height: 4).padding(.bottom, 7)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(.white.opacity(0.28), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.30), radius: 12, y: 7)
    }

    #if os(macOS)
    private func macNote(_ content: ProPreviewContent, color: NoteColor) -> some View {
        MacProPreviewNote(content: content, noteColor: color, backgroundOpacity: 0.8, singleMemoScale: 0.8)
            .frame(width: 177, height: 216)
            .background(MacProPreviewNoteBackground(noteColor: color, backgroundOpacity: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(0.41)
            .frame(width: 72, height: 89)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .offset(y: color == .yellow ? -12 : 16)
    }
    #else
    private func desktopNote(_ content: ProPreviewContent, color: NoteColor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.note.title ?? "").font(.system(size: 12, weight: .bold)).lineLimit(2)
            ForEach(content.tasks.prefix(3), id: \.id) { task in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9))
                    Text(task.richText.text).font(.system(size: 9)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
        .padding(8)
        .frame(width: 150, height: 190, alignment: .topLeading)
        .background(previewColor(color).opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
    }
    #endif

    private func phoneCard(_ content: ProPreviewContent, color: NoteColor) -> some View {
        #if os(iOS)
        return iosCard(content, color: color)
        #else
        return Group {
            if content.note.kind == .singleTask, let task = content.tasks.first {
                Text(task.richText.text)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(content.note.title ?? "").font(.system(size: 8, weight: .semibold)).lineLimit(2)
                    ForEach(content.tasks.prefix(3), id: \.id) { task in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 7))
                            Text(task.richText.text).font(.system(size: 7)).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(.black)
        .padding(7)
        .frame(width: 100, height: 138, alignment: .topLeading)
        .background(previewColor(color), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.20)))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        #endif
    }

    private func previewColor(_ color: NoteColor) -> Color {
        #if os(macOS)
        Color(nsColor: color.nsColor)
        #else
        color.swiftUIColor
        #endif
    }

    #if os(iOS)
    private func iosCard(_ content: ProPreviewContent, color: NoteColor) -> some View {
        let summary = NoteTaskSummary(
            noteID: content.note.id,
            tasks: TaskHierarchy.leafTasks(in: content.tasks)
        )
        let previews = content.tasks.enumerated().map { index, task in
            NoteTaskPreview(task, subtaskProgress: TaskHierarchy.subtaskProgress(at: index, in: content.tasks))
        }
        return NoteCard(
            note: content.note,
            summary: summary,
            tasks: previews,
            style: .deck,
            height: 150,
            contentScale: content.note.kind == .singleTask ? 0.72 : 0.58,
            rename: {},
            delete: {}
        )
        .frame(width: 100)
    }
    #endif
}
