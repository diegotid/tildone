//
//  Settings.swift
//  Tildone
//
//  Created by Diego Rivera on 6/1/24.
//

import SwiftUI

// MARK: Settings view

struct SettingsForm: View {
    @AppStorage("taskLineTruncation") private var taskLineTruncation: TaskLineTruncation = .single
    
    var body: some View {
        Form {
            Section {
                Launcher.Toggle()
            } header: {
                Text(Copy.settingsSectionGeneral)
                    .bold()
            }
            Divider()
                .padding(.top, 8)
            Section {
                Text(Copy.taskPlaceholder)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 18) {
                    VStack {
                        Image("taskTruncationSingle")
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .if(taskLineTruncation == .single) { view in
                                view.overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.accent, lineWidth: 6)
                                )
                            }
                        Text(Copy.settingsSectionAppearanceSingle)
                            .if(taskLineTruncation == .single) { view in
                                view.bold()
                            }
                    }
                    .onTapGesture {
                        taskLineTruncation = .single
                    }
                    VStack {
                        Image("taskTruncationMultiple")
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .if(taskLineTruncation == .multiple) { view in
                                view.overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.accent, lineWidth: 6)
                                )
                            }
                        Text(Copy.settingsSectionAppearanceMultiple)
                            .if(taskLineTruncation == .multiple) { view in
                                view.bold()
                            }
                    }
                    .onTapGesture {
                        taskLineTruncation = .multiple
                    }
                }
            } header: {
                Text(Copy.settingsSectionAppearance)
                    .bold()
            }
        }
        .padding(24)
        .frame(maxWidth: 470, maxHeight: 330)
    }
}

// MARK: Enum types

enum TaskLineTruncation: Int {
    case single = 1
    case multiple
}

// MARK: Settings preview

#if DEBUG
#Preview {
    return SettingsForm()
}
#endif
