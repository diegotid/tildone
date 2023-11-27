//
//  LicenseType.swift
//  Tildone
//
//  Created by Diego Rivera on 28/11/23.
//

import SwiftUI

enum LicenseType {
    case free
    case pro
}

private struct LicenseTypeKey: EnvironmentKey {
    static let defaultValue: LicenseType = .free
}

extension EnvironmentValues {
    var license: LicenseType {
        get { self[LicenseTypeKey.self] }
        set { self[LicenseTypeKey.self] = newValue }
    }
}
