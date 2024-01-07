//
//  Settings.swift
//  Tildone
//
//  Created by Diego Rivera on 6/1/24.
//

import SwiftUI

struct SettingsForm: View {
    
    var body: some View {
        Form {
            Section {
                Launcher.Toggle()
            } header: {
                Text(Copy.settingsSectionGeneral)
                    .bold()
            }
        }
        .padding()
        .padding(.vertical, 20)
    }
}
