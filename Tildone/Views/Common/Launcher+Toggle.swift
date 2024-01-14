//
//  Launcher+Toggle.swift
//  Tildone
//
//  Created by Diego Rivera on 12/1/24.
//

import SwiftUI

extension Launcher {
    
    public struct Toggle: View {
        @ObservedObject private var launcher = Launcher.watching
        
        public var body: some View {
            SwiftUI.Toggle(isOn: $launcher.isEnabled) {
                Text("Open at login")
            }
        }
    }
}
