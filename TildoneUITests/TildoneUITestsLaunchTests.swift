//
//  TildoneUITestsLaunchTests.swift
//  TildoneUITests
//
//  Created by Diego Rivera on 5/11/23.
//

import XCTest

final class TildoneUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments.append("--tildone-ui-test")
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
