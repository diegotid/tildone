//
//  UpdateChecker.swift
//  Tildone
//
//  Created by Diego Rivera on 12/1/24.
//

import Foundation

struct UpdateChecker {
    static func getAppStoreVersion(completion: @escaping (String?) -> Void) {
        guard let bundleId = Bundle.main.bundleIdentifier,
              let lookup = URL(string: "\(UpdateChecker.Remote.appStoreLookupUrl)?bundleId=\(bundleId)")
        else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: lookup) { (data, response, error) in
            guard let optionalData = data,
                  error == nil
            else {
                completion(nil)
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(
                    with: optionalData,
                    options: []
                ) as? [String: Any] else {
                    completion(nil)
                    return
                }
                guard let results = json[UpdateChecker.Remote.appStoreResultsKey] as? [[String: Any]],
                      let version = results.first?[UpdateChecker.Remote.appStoreVersionKey] as? String
                else {
                    completion(nil)
                    return
                }
                completion(version)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}

extension UpdateChecker {
    enum Remote {
        static let appStoreLookupUrl: String = "https://itunes.apple.com/lookup"
        static let appStoreAppUrl: String = "https://apps.apple.com/app/tildone/id6473126292"
        static let appStoreResultsKey: String = "results"
        static let appStoreVersionKey: String = "version"
    }
}
