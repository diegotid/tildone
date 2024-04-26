//
//  Settings.swift
//  Tildone
//
//  Created by Diego Rivera on 6/1/24.
//

import SwiftUI

// MARK: Settings view

struct SettingsForm: View {
    
    @AppStorage("fontSize")
    private var fontSize = Double(FontSize.small.rawValue)
    
    @AppStorage("taskLineTruncation")
    private var taskLineTruncation: TaskLineTruncation = .single
    
    @AppStorage("selectedArrangementCorner")
    private var selectedArrangementCorner: ArrangementCorner = .bottomLeft
    
    @AppStorage("selectedArrangementAlignment")
    private var selectedArrangementAlignment: ArrangementAlignment = .horizontal
    
    @AppStorage("selectedArrangementCornerMargin")
    private var selectedArrangementCornerMargin: ArrangementSpacing = .medium
    
    @AppStorage("selectedArrangementSpacing")
    private var selectedArrangementSpacing: ArrangementSpacing = .minimum
    
    var body: some View {
        ScrollView {
            Form {
                VStack(alignment: .leading) {
                    Section {
                        Launcher.Toggle()
                    } header: {
                        Text("General")
                            .bold()
                    }
                    Divider()
                        .padding(.top, 8)
                    Section {
                        VStack(alignment: .leading) {
                            fontSizeSettings()
                            taskAppearanceSettings()
                            desktopAppearanceSettings()
                        }
                    } header: {
                        Text("Appearance")
                            .bold()
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 470, height: 635)
    }
}

// MARK: Form components

private extension SettingsForm {
    
    @ViewBuilder
    func fontSizeSettings() -> some View {
        Text("Font size")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 1)
        HStack {
            Spacer()
            Text("Task text sample")
                .font(.system(size: CGFloat(FontSize(rawValue: fontSize)!.toValue())))
            Spacer()
        }
        Slider(
            value: $fontSize,
            in: Double(FontSize.xSmall.rawValue)...Double(FontSize.xLarge.rawValue),
            step: 1
        )
        .padding(.trailing, 10)
        HStack {
            ForEach(FontSize.allCases, id: \.self) { fontSize in
                Text(fontSize.toString())
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 14)
    }
    
    @ViewBuilder
    func taskAppearanceSettings() -> some View {
        Text("Task")
            .font(.subheadline)
            .foregroundColor(.secondary)
        HStack(spacing: 18) {
            taskAppearanceSample(for: .single)
            taskAppearanceSample(for: .multiple)
        }
    }
    
    @ViewBuilder
    func desktopAppearanceSettings() -> some View {
        Text("Desktop")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 8)
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: SettingsForm.alignment(for: selectedArrangementCorner)) {
                Image("desktop")
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
            VStack {
                Text("How to arrange your notes\n(when menu command used or ⇧⌘A pressed):")
                    .frame(width: 160, alignment: .leading)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 5)
                    .padding(.leading, 5)
                desktopPickers()
            }
        }
    }

    @ViewBuilder
    func taskAppearanceSample(for option: TaskLineTruncation) -> some View {
        VStack {
            Image(SettingsForm.imageNameForTaskAppearance(with: option))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .if(taskLineTruncation == option) { view in
                    view.overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.accent, lineWidth: 6)
                    )
                }
            SettingsForm.taskAppearanceText(with: option)
                .if(taskLineTruncation == option) { view in
                    view.bold()
                }
        }
        .onTapGesture {
            taskLineTruncation = option
        }
    }
    
    @ViewBuilder
    func sampleDesktopNotes() -> some View {
        ForEach(0..<3) { _ in
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.noteBackground))
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
        Picker(selection: $selectedArrangementCorner) {
            Text("Bottom left corner")
                .tag(ArrangementCorner.bottomLeft)
            Text("Bottom right corner")
                .tag(ArrangementCorner.bottomRight)
            Text("Top right corner")
                .tag(ArrangementCorner.topRight)
            Text("Top left corner")
                .tag(ArrangementCorner.topLeft)
        } label: {
            EmptyView()
        }
        Picker(selection: $selectedArrangementAlignment) {
            Text("Horizontal")
                .tag(ArrangementAlignment.horizontal)
            Text("Vertical")
                .tag(ArrangementAlignment.vertical)
        } label: {
            EmptyView()
        }
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
        case .single: Text("Single line with ellipsis")
        case .multiple: Text("Multiline")
        }
    }
}

// MARK: Enum types

enum FontSize: Int, CaseIterable {
    case xSmall = 0
    case small
    case medium
    case large
    case xLarge
    
    init?(rawValue: Double) {
        self = FontSize.allCases[Int(rawValue)]
    }
    
    func toValue() -> Int {
        switch self {
        case .xSmall: 10
        case .small: 13
        case .medium: 16
        case .large: 20
        case .xLarge: 24
        }
    }
    
    func toString() -> String {
        switch self {
        case .xSmall: String(localized: "X Small")
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .xLarge: String(localized: "X Large")
        }
    }
}

enum TaskLineTruncation: Int {
    case single = 1
    case multiple
}

enum ArrangementCorner: Int {
    case bottomLeft = 0
    case bottomRight
    case topRight
    case topLeft
}

enum ArrangementAlignment: Int {
    case horizontal = 0
    case vertical
}

enum ArrangementSpacing: Int {
    case minimum = 20
    case medium = 40
    case maximum = 60
}

// MARK: Settings preview

#if DEBUG
#Preview {
    return SettingsForm()
}
#endif
