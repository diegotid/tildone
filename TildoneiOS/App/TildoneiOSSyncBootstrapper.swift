//
//  TildoneiOSSyncBootstrapper.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import Foundation
import TildoneSync

enum TildoneiOSSyncBootstrapper {
    static var cloudKitEnvironment: CloudKitEnvironment {
        compiledBuildMode.cloudKitEnvironment
    }

    static var featureEnabled: Bool {
        TransportDefaultPolicy.isEnabled(
            buildMode: compiledBuildMode,
            isTestProcess: isTestProcess
        )
    }

    private static var compiledBuildMode: TransportBuildMode {
#if DEBUG
        .debug
#else
        .release
#endif
    }

    static var isTestProcess: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["TILDONE_UI_TESTING"] == "1" ||
            environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCInjectBundleInto"] != nil ||
            NSClassFromString("XCTestCase") != nil
    }
}
