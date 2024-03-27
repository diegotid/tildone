//
//  UpdateChecker.swift
//  Tildone
//
//  Created by Diego Rivera on 12/1/24.
//

import Foundation
import StoreKit

struct UpdateChecker {
    
    static func getAppVersion(completion: @escaping (String?) -> Void) {
        Task {
            do {
                let app = try await AppTransaction.shared
                switch app {
                case .verified(let installed):
                    completion(installed.appVersion)
                default:
                    completion(nil)
                }
            } catch {
                debugPrint(error.localizedDescription)
                completion(nil)
            }
        }
    }
    
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
        let checkWhatsNewTask = Todo("Check release notes", at: 0)
        checkList.topic = "Updated to v\(version)"
        checkList.items = [checkWhatsNewTask]
        checkList.systemURL = URL(string: Remote.releaseNotesUrl)
        checkList.systemContent = """
        Tildone has been updated featuring now:
        \u{2022} Open at login
        \u{2022} Focus filters
        \u{2022} Arrange notes
        \u{2022} Spanish, French and Chinese
        \u{2022} Several other improvements
        """
        return checkList
    }
}

extension UpdateChecker {
    enum Local {
        static let knownVersionFlag: String = "knownAppVersion"
    }
    enum Remote {
        static let appStoreAppUrl: String = "https://apps.apple.com/app/tildone/id6473126292"
        static let releaseNotesUrl: String = "http://cuatro.studio/tildone/release"
    }
}
