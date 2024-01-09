//
//  Settings.swift
//  Tildone
//
//  Created by Diego Rivera on 6/1/24.
//

import SwiftUI

// MARK: Settings view

struct SettingsForm: View {
    
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
                        Text(Copy.settingsSectionGeneral)
                            .bold()
                    }
                    Divider()
                        .padding(.top, 8)
                    Section {
                        VStack(alignment: .leading) {
                            taskAppearanceSettings()
                            desktopAppearanceSettings()
                        }
                    } header: {
                        Text(Copy.settingsSectionAppearance)
                            .bold()
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 470, height: 520)
    }
}

// MARK: Form components

private extension SettingsForm {
    
    @ViewBuilder
    func taskAppearanceSettings() -> some View {
        Text(Copy.taskPlaceholder)
            .font(.subheadline)
            .foregroundColor(.secondary)
        HStack(spacing: 18) {
            taskAppearanceSample(for: .single)
            taskAppearanceSample(for: .multiple)
        }
    }
    
    @ViewBuilder
    func desktopAppearanceSettings() -> some View {
        Text(Copy.desktopPlaceholder)
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
                Text(Copy.settingsArrangementDescription)
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
            Text(SettingsForm.copyForTaskAppearance(with: option))
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
            Text(Copy.settingsArrangementCornerBottomLeft)
                .tag(ArrangementCorner.bottomLeft)
            Text(Copy.settingsArrangementCornerBottomRight)
                .tag(ArrangementCorner.bottomRight)
            Text(Copy.settingsArrangementCornerTopRight)
                .tag(ArrangementCorner.topRight)
            Text(Copy.settingsArrangementCornerTopLeft)
                .tag(ArrangementCorner.topLeft)
        } label: {
            EmptyView()
        }
        Picker(selection: $selectedArrangementAlignment) {
            Text(Copy.settingsArrangementAlignmentHorizontal)
                .tag(ArrangementAlignment.horizontal)
            Text(Copy.settingsArrangementAlignmentVertical)
                .tag(ArrangementAlignment.vertical)
        } label: {
            EmptyView()
        }
        Picker(selection: $selectedArrangementCornerMargin) {
            Text(Copy.settingsArrangementMarginMinimum)
                .tag(ArrangementSpacing.minimum)
            Text(Copy.settingsArrangementMarginMedium)
                .tag(ArrangementSpacing.medium)
            Text(Copy.settingsArrangementMarginMaximum)
                .tag(ArrangementSpacing.maximum)
        } label: {
            EmptyView()
        }
        Picker(selection: $selectedArrangementSpacing) {
            Text(Copy.settingsArrangementSpacingMinimum)
                .tag(ArrangementSpacing.minimum)
            Text(Copy.settingsArrangementSpacingMedium)
                .tag(ArrangementSpacing.medium)
            Text(Copy.settingsArrangementSpacingMaximum)
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
    
    static func copyForTaskAppearance(with option: TaskLineTruncation) -> String {
        switch option {
        case .single: Copy.settingsSectionAppearanceSingle
        case .multiple: Copy.settingsSectionAppearanceMultiple
        }
    }
}

// MARK: Enum types

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
