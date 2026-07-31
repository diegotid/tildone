//
//  TildoneiOSSyncBootstrapper.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import Foundation

enum TildoneiOSSyncBootstrapper {
    static var featureEnabled: Bool {
#if DEBUG
        !isTestProcess && ProcessInfo.processInfo.environment["TILDONE_ENABLE_CLOUDKIT_SYNC"] == "1"
#else
        false
#endif
    }

    private static var isTestProcess: Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCInjectBundleInto"] != nil ||
            NSClassFromString("XCTestCase") != nil
#else
        false
#endif
    }
}
