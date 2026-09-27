import SwiftUI
import TildoneDomain

struct ProPreviewScene: View {
    let feature: ProFeature
    let locale: Locale
    var noteImage: NSImage? = nil
    var noteBackgroundImage: NSImage? = nil
    var elapsedTime: TimeInterval = 0
    var reduceMotion = false
    var usesFixedTime = false
    var canvasSize = CGSize(width: 360, height: 360)

    private var noteScale: CGFloat { min(1, canvasSize.height / 360, canvasSize.width / 360) }
    @State private var isHoveringNote = false
    @AppStorage(NoteColor.storageKey) private var noteColorRawValue = NoteColor.yellow.legacyRawValue
    @AppStorage(ArrangementCorner.storageKey) private var gatheringCorner: ArrangementCorner = .bottomLeft
    @AppStorage(ArrangementSpacing.cornerStorageKey) private var gatheringMargin: ArrangementSpacing = .medium
    @AppStorage(ArrangementDockSpace.storageKey) private var reservesDockSpace = false
    @AppStorage(NoteWindowBackground.opacityStorageKey) private var backgroundOpacity = Double(NoteWindowBackground.defaultAlpha)

    private var defaultNoteColor: NoteColor { NoteColor(legacyRawValue: noteColorRawValue) ?? .yellow }

    private var revealProgress: Double {
        if isHoveringNote { return 1 }
        return reduceMotion ? 0 : ProPreviewMotion.revealProgress(at: elapsedTime)
    }

    var body: some View {
        ZStack {
            SettingsPreviewBackground(size: canvasSize)
            switch feature {
            case .gathering:
                GatherPreview(
                    corner: gatheringCorner, margin: gatheringMargin, reservesDockSpace: reservesDockSpace,
                    noteColor: defaultNoteColor, backgroundOpacity: backgroundOpacity,
                    canvasSize: canvasSize,
                    previewDate: usesFixedTime ? Date(timeIntervalSinceReferenceDate: elapsedTime) : nil,
                    reduceMotion: reduceMotion, showsWindowControls: false, dockEdgeInset: 0
                )
            case .dimming:
                DimmingPreview(
                    noteColor: defaultNoteColor, backgroundOpacity: backgroundOpacity, fontSize: 13,
                    taskLineTruncation: .multiple,
                    canvasSize: canvasSize,
                    previewDate: usesFixedTime ? Date(timeIntervalSinceReferenceDate: elapsedTime) : nil,
                    reduceMotion: reduceMotion, windowButtonSize: 12, corner: gatheringCorner,
                    noteSize: CGSize(width: 216, height: 288), noteScale: noteScale
                )
            case .background:
                note.scaleEffect(0.72 * noteScale).position(x: canvasSize.width * 121 / 360, y: canvasSize.height * 149 / 360)
                otherWindow.scaleEffect(noteScale).position(x: canvasSize.width * 211 / 360, y: canvasSize.height * 213 / 360)
            default:
                note.scaleEffect(noteScale)
                    .onHover { isHoveringNote = $0 }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isHoveringNote)
                if feature == .blur && !reduceMotion && !isHoveringNote {
                    let progress = ProPreviewMotion.pointerProgress(at: elapsedTime)
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 25 * noteScale, weight: .semibold))
                        .foregroundStyle(.black)
                        .shadow(color: .white, radius: 1)
                        .position(x: (331 - progress * 114) * canvasSize.width / 360,
                                  y: (333 - progress * 124) * canvasSize.height / 360)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .overlay(alignment: .topTrailing) {
            if feature == .blur || feature == .background {
                Image(systemName: "moon.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .padding(16)
            }
        }
        .clipped()
    }

    private var note: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index == 1 ? Color.yellow : .gray.opacity(0.4))
                        .frame(width: 12, height: 12)
                }
                Spacer()
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            Group {
                if let noteImage {
                    Image(nsImage: noteImage).resizable()
                } else {
                    MacProPreviewNote(content: ProPreviewContent(feature: feature, locale: locale, noteColor: defaultNoteColor),
                                      noteColor: defaultNoteColor, backgroundOpacity: backgroundOpacity)
                }
            }
            .frame(width: 216, height: 262)
            .blur(radius: feature == .blur ? 4 * (1 - revealProgress) : 0)
        }
        .frame(width: 216, height: 288)
        .background {
            if let noteBackgroundImage {
                Image(nsImage: noteBackgroundImage).resizable()
            } else {
                MacProPreviewNoteBackground(noteColor: defaultNoteColor, backgroundOpacity: backgroundOpacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
    }

    private var otherWindow: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle().fill([Color.red, .yellow, .green][index])
                        .frame(width: 12, height: 12)
                }
                Spacer()
                Text("Another window").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.black.opacity(0.65))
            }
            Divider()
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: CGFloat([165, 125, 145][index]), height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 244, height: 238)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(.black.opacity(0.12), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .environment(\.colorScheme, .light)
    }

}
