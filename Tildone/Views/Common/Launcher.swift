//
//  Launcher.swift
//  Tildone
//
//  Created by Diego Rivera on 6/1/24.
//

import SwiftUI
import ServiceManagement

public enum Launcher {
    private static let watching = Watcher()
    
    public static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            watching.objectWillChange.send()
            do {
                switch newValue {
                case true:
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                    try SMAppService.mainApp.register()
                case false:
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                debugPrint("Error on changing launch on startup setting to \(newValue)")
            }
        }
    }
    
    public struct Toggle: View {
        @ObservedObject private var launcher = Launcher.watching
        
        public var body: some View {
            SwiftUI.Toggle(isOn: $launcher.isEnabled) {
                Text(Copy.openOnLoginLabel)
            }
        }
    }
}

private extension Launcher {
    final class Watcher: ObservableObject {
        var isEnabled: Bool {
            get {
                Launcher.isEnabled
            }
            set {
                Launcher.isEnabled = newValue
            }
        }
    }
}
