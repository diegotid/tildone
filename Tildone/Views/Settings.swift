//
//  Settings.swift
//  Tildone
//
//  Created by Diego Rivera on 6/1/24.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: Settings view

struct SettingsForm: View {
    
    @AppStorage(FontSize.storageKey)
    private var fontSize = Double(FontSize.small.rawValue)
    
    @AppStorage(TaskLineTruncation.storageKey)
    private var taskLineTruncation: TaskLineTruncation = .single
    
    @AppStorage(ArrangementCorner.storageKey)
    private var selectedArrangementCorner: ArrangementCorner = .bottomLeft
    
    @AppStorage(ArrangementAlignment.storageKey)
    private var selectedArrangementAlignment: ArrangementAlignment = .horizontal
    
    @AppStorage(ArrangementSpacing.cornerStorageKey)
    private var selectedArrangementCornerMargin: ArrangementSpacing = .medium
    
    @AppStorage(ArrangementSpacing.sideStorageKey)
    private var selectedArrangementSpacing: ArrangementSpacing = .minimum
    
    @AppStorage(NoteColor.storageKey)
    private var noteColor: NoteColor = .yellow
    
    @AppStorage(NoteWindowBackground.opacityStorageKey)
    private var noteBackgroundOpacity = Double(NoteWindowBackground.defaultAlpha)

    @StateObject
    private var sampleNoteData = SampleNoteData()

    var body: some View {
        ScrollView {
            Form {
                VStack(alignment: .leading) {
                    Section {
                        VStack(alignment: .leading) {
                            Launcher.Toggle()
                            Text("Start Tildone automatically when you log in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    } header: {
                        Text("General")
                            .bold()
                    }
                    Divider()
                        .padding(.vertical, 16)
                    Section {
                        VStack(alignment: .leading) {
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading) {
                                    noteColorSettings()
                                    fontSizeSettings()
                                    taskWrappingSettings()
                                }
                                Spacer()
                                notePreview()
                            }
                        }
                    } header: {
                        Text("General")
                            .bold()
                    }
                    Divider()
                        .padding(.vertical, 16)
                    Section {
                        HStack(alignment: .bottom, spacing: 12) {
                            desktopAppearanceSettings()
                            Spacer()
                            desktopPreview()
                        }
                    } header: {
                        Text("Desktop placement")
                            .bold()
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 520, height: 660)
    }
}

// MARK: Form components

private extension SettingsForm {
    
    @ViewBuilder
    func fontSizeSettings() -> some View {
        Text("Font size")
            .foregroundColor(.secondary)
            .padding(.top, 3)
        Slider(
            value: $fontSize,
            in: Double(FontSize.xSmall.rawValue)...Double(FontSize.xLarge.rawValue)
        ) {
            Text("Font size")
        }
        .labelsHidden()
        .frame(width: 200)
    }
    
    @ViewBuilder
    func taskWrappingSettings() -> some View {
        Text("Task wrapping")
            .foregroundColor(.secondary)
            .padding(.top, 3)
        Picker("", selection: $taskLineTruncation) {
            SettingsForm.taskAppearanceText(with: .single)
                .tag(TaskLineTruncation.single)
            SettingsForm.taskAppearanceText(with: .multiple)
                .tag(TaskLineTruncation.multiple)
        }
        .pickerStyle(.radioGroup)
        .padding(.vertical, 1)
    }
    
    @ViewBuilder
    func noteColorSettings() -> some View {
        Text("Note color")
            .foregroundColor(.secondary)
            .padding(.top, 8)
        HStack(spacing: 9) {
            ForEach(NoteColor.allCases) { option in
                noteColorSample(for: option)
            }
        }
        Text("Background opacity")
            .foregroundColor(.secondary)
            .padding(.top, 8)
        Slider(value: $noteBackgroundOpacity, in: 0...1) {
            Text("Background opacity")
        }
        .labelsHidden()
        .frame(width: 200)
    }
    
    @ViewBuilder
    func desktopAppearanceSettings() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When menu command used or ⇧⌘A pressed:")
                .foregroundColor(.secondary)
            desktopPickers()
        }
    }
    
    @ViewBuilder
    func noteColorSample(for option: NoteColor) -> some View {
        let isSelected = noteColor == option
        RoundedRectangle(cornerRadius: 6)
            .fill(option.fillStyle)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : .clear,
                            lineWidth: isSelected ? 5 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                noteColor = option
            }
            .help(option.label)
    }
    
    @ViewBuilder
    func notePreview() -> some View {
        ZStack {
            Image("desktop")
            ZStack {
                VisualEffectBlurView(material: .hudWindow, blendingMode: .withinWindow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: noteColor.nsColor).opacity(noteBackgroundOpacity))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 3)
                VStack(alignment: .leading) {
                    HStack {
                        ForEach(0..<3) { index in
                            Circle()
                                .frame(width: 15, height: 15)
                                .foregroundStyle(index == 1 ? Color.yellow : .gray.opacity(0.4))
                        }
                    }
                    .padding(.top, 9)
                    .padding(.leading, 9)
                    Note()
                        .todoList(sampleNoteData.list)
                        .previewMode()
                        .environment(\.modelContext, sampleNoteData.container.mainContext)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: Layout.defaultNoteWidth, height: Layout.defaultNoteHeight)
            .scaleEffect(0.75)
            .padding(.top, 110)
        }
        .frame(width: 240, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    func desktopPreview() -> some View {
        ZStack(alignment: SettingsForm.alignment(for: selectedArrangementCorner)) {
            Image("desktop")
                .frame(width: 240, height: 160)
            switch selectedArrangementAlignment {
            case .horizontal:
                HStack {
                    sampleDesktopNotes()
                }
                .padding(CGFloat(selectedArrangementCornerMargin.rawValue / 4))
            case .vertical:
                VStack {
                    sampleDesktopNotes()
                }
                .padding(CGFloat(selectedArrangementCornerMargin.rawValue / 4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    func sampleDesktopNotes() -> some View {
        ForEach(0..<3) { _ in
            ZStack {
                VisualEffectBlurView(material: .hudWindow, blendingMode: .withinWindow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: noteColor.nsColor).opacity(noteBackgroundOpacity))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 3)
            }
            .frame(width: 24, height: 30)
            .padding(
                SettingsForm.edge(
                    for: selectedArrangementCorner,
                    withAlignment: selectedArrangementAlignment
                ),
                CGFloat(selectedArrangementSpacing.rawValue / 24)
            )
        }
    }
    
    @ViewBuilder
    func desktopPickers() -> some View {
        let pickerWidth: CGFloat = 150
        VStack(alignment: .leading, spacing: 8) {
            Picker(selection: $selectedArrangementCorner) {
                Text("Bottom left")
                    .tag(ArrangementCorner.bottomLeft)
                Text("Bottom right")
                    .tag(ArrangementCorner.bottomRight)
                Text("Top right")
                    .tag(ArrangementCorner.topRight)
                Text("Top left")
                    .tag(ArrangementCorner.topLeft)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker(selection: $selectedArrangementAlignment) {
                Text("Horizontal")
                    .tag(ArrangementAlignment.horizontal)
                Text("Vertical")
                    .tag(ArrangementAlignment.vertical)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker(selection: $selectedArrangementCornerMargin) {
                Text("Minimum margin")
                    .tag(ArrangementSpacing.minimum)
                Text("Medium margin")
                    .tag(ArrangementSpacing.medium)
                Text("Maximum margin")
                    .tag(ArrangementSpacing.maximum)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker(selection: $selectedArrangementSpacing) {
                Text("Minimum spacing")
                    .tag(ArrangementSpacing.minimum)
                Text("Medium spacing")
                    .tag(ArrangementSpacing.medium)
                Text("Maximum spacing")
                    .tag(ArrangementSpacing.maximum)
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: pickerWidth, alignment: .leading)
    }
}

// MARK: Sample note data

@MainActor
private final class SampleNoteData: ObservableObject {
    let container: ModelContainer
    let list: TodoList

    init() {
        let schema = Schema([Todo.self, TodoList.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create sample model container: \(error)")
        }
        list = SampleNoteData.makeSampleList()
        container.mainContext.insert(list)
        for task in list.items {
            container.mainContext.insert(task)
        }
        do {
            try container.mainContext.save()
        } catch {
            debugPrint(error.localizedDescription)
        }
    }

    private static func makeSampleList() -> TodoList {
        let list = TodoList()
        list.topic = "Sample note"
        let doneTask = Todo("Done task", at: 1)
        doneTask.setDone()
        let longTask = Todo("A longer task that should wrap or truncate based on settings", at: 2)
        let shortTask = Todo("Another task", at: 3)
        list.items = [doneTask, longTask, shortTask]
        for task in list.items {
            task.list = list
        }
        return list
    }
}

private struct VisualEffectBlurView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: Private functions

extension SettingsForm {
    
    static func alignment(for corner: ArrangementCorner) -> Alignment {
        switch corner {
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        case .topRight: .topTrailing
        case .topLeft: .topLeading
        }
    }
    
    static func edge(
        for corner: ArrangementCorner,
        withAlignment align: ArrangementAlignment
    ) -> Edge.Set {
        switch align {
        case .horizontal:
            switch corner {
            case .bottomLeft, .topLeft:
                return .trailing
            case .bottomRight, .topRight:
                return .leading
            }
        case .vertical:
            switch corner {
            case .bottomLeft, .bottomRight:
                return .top
            case .topLeft, .topRight:
                return .bottom
            }
        }
    }
    
    static func imageNameForTaskAppearance(with option: TaskLineTruncation) -> String {
        switch option {
        case .single: "taskTruncationSingle"
        case .multiple: "taskTruncationMultiple"
        }
    }
    
    static func taskAppearanceText(with option: TaskLineTruncation) -> Text {
        switch option {
        case .single: Text("Single line (ellipsis)")
        case .multiple: Text("Wrap to multiple lines")
        }
    }
}

// MARK: Enum types

enum FontSize: Double, CaseIterable {
    case xSmall = 10
    case small = 13
    case medium
    case large
    case xLarge = 24
    
    init?(fromLegacySetting legacyValue: Double) {
        self = FontSize.allCases[Int(legacyValue)]
    }
    
    static let storageKey = "fontSize"
}

enum TaskLineTruncation: Int {
    case single = 1
    case multiple
    
    static let storageKey = "taskLineTruncation"
}

enum ArrangementCorner: Int {
    case bottomLeft = 0
    case bottomRight
    case topRight
    case topLeft
    
    static let storageKey = "selectedArrangementCorner"
}

enum ArrangementAlignment: Int {
    case horizontal = 0
    case vertical
    
    static let storageKey = "selectedArrangementAlignment"
}

enum ArrangementSpacing: Int {
    case minimum = 20
    case medium = 40
    case maximum = 60
    
    static let sideStorageKey = "selectedArrangementSpacing"
    static let cornerStorageKey = "selectedArrangementCornerMargin"
}

// MARK: Color extension

extension NoteColor {
    static let storageKey = "noteColor"
    private static let legacyTranslucentRawValue = 6

    static func current(from defaults: UserDefaults = .standard) -> NoteColor {
        let rawValue = defaults.integer(forKey: storageKey)
        if rawValue == legacyTranslucentRawValue {
            defaults.set(NoteColor.yellow.rawValue, forKey: storageKey)
            if defaults.object(forKey: NoteWindowBackground.opacityStorageKey) == nil {
                defaults.set(0.0, forKey: NoteWindowBackground.opacityStorageKey)
            }
        }
        return NoteColor(rawValue: rawValue) ?? .yellow
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return .noteBackground
        case .green: return .systemNoteBackground
        case .blue: return .noteBlueBackground
        case .pink: return .notePinkBackground
        case .purple: return .notePurpleBackground
        case .orange: return .noteOrangeBackground
        }
    }

    var fillStyle: AnyShapeStyle {
        return AnyShapeStyle(Color(nsColor: nsColor))
    }
}

// MARK: Settings preview

#if DEBUG
#Preview {
    return SettingsForm()
}
#endif
