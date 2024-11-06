//
//  UpdateChecker.swift
//  Tildone
//
//  Created by Diego Rivera on 12/1/24.
//

import Foundation
import StoreKit

struct UpdateChecker {
    
    static func getNewReleaseCheckList() async -> TodoList? {
        do {
            let app = try await AppTransaction.shared
            if case .verified(let installed) = app {
                let known: String? = UserDefaults.standard.string(forKey: Local.knownVersionFlag)
                let isKnown: Bool = installed.appVersion == known
                let isUpdated: Bool = installed.appVersion != installed.originalAppVersion
                if isUpdated && !isKnown {
                    UserDefaults.standard.setValue(installed.appVersion, forKey: Local.knownVersionFlag)
                    return releaseCheckList(version: installed.appVersion)
                }
            }
            return nil
        } catch {
            debugPrint(error.localizedDescription)
            return nil
        }
    }
    
    private static func releaseCheckList(version: String) -> TodoList {
        let checkList = TodoList()
        let checkWhatsNewTask = Todo(String(localized: "Check release notes"), at: 0)
        checkList.topic = String(localized: "Updated to v\(version)")
        checkList.items = [checkWhatsNewTask]
        checkList.systemURL = URL(string: Remote.releaseNotesUrl)
        checkList.systemContent = String(localized: """
        New features:
        \u{2022} Restyle window buttons to standard
        \u{2022} Show topic on minimized notes
        \u{2022} Bug fixing
        
        From the previous release:
        \u{2022} Every note can now be minimized into a progress gauge
        \u{2022} Empty tasks in a note can be deleted from the keyboard
        """)
        return checkList
    }
}

extension UpdateChecker {
    enum Local {
        static let knownVersionFlag: String = "knownAppVersion"
    }
    enum Remote {
        static let releaseNotesUrl: String = "http://cuatro.studio/tildone/release"
    }
}
