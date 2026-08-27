//
//  TildoneTests.swift
//  TildoneTests
//

import CloudKit
import SwiftUI
import XCTest
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

final class TildoneTests: XCTestCase {
    func testNoteContentForegroundUsesTheSameContrastRuleInNotesAndPreviews() {
        XCTAssertFalse(
            NoteContentForeground.usesLightText(
                colorScheme: .light,
                backgroundOpacity: 0
            )
        )
        XCTAssertFalse(
            NoteContentForeground.usesLightText(
                colorScheme: .dark,
                backgroundOpacity: 0.5
            )
        )
        XCTAssertTrue(
            NoteContentForeground.usesLightText(
                colorScheme: .dark,
                backgroundOpacity: 0.49
            )
        )
    }

    func testSettingsHeightFollowsContentAndNeverExceedsItsFixedWidth() {
        let hostingView = NSHostingView(rootView: SettingsForm())
        XCTAssertEqual(hostingView.fittingSize, CGSize(width: 600, height: 250))

        XCTAssertEqual(
            SettingsForm.preferredWindowHeight(
                contentHeight: 40,
                width: 600
            ),
            40
        )
        XCTAssertEqual(
            SettingsForm.preferredWindowHeight(
                contentHeight: 200,
                width: 600
            ),
            200
        )
        XCTAssertEqual(
            SettingsForm.preferredWindowHeight(
                contentHeight: 700,
                width: 600
            ),
            600
        )
    }

    func testBackgroundTransparencyControllerIsTheInverseOfStoredOpacity() {
        XCTAssertEqual(SettingsForm.backgroundTransparency(fromOpacity: 0.7), 0.3, accuracy: 0.0001)
        XCTAssertEqual(SettingsForm.backgroundOpacity(fromTransparency: 0.3), 0.7, accuracy: 0.0001)
        XCTAssertEqual(SettingsForm.backgroundTransparency(fromOpacity: -1), 1)
        XCTAssertEqual(SettingsForm.backgroundOpacity(fromTransparency: 2), 0)
    }

    func testDimmingPreviewUsesSlowEightSecondCycle() {
        XCTAssertEqual(
            SettingsForm.opacityPreviewValue(at: Date(timeIntervalSinceReferenceDate: 0)),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SettingsForm.opacityPreviewValue(at: Date(timeIntervalSinceReferenceDate: 4)),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SettingsForm.opacityPreviewValue(at: Date(timeIntervalSinceReferenceDate: 8)),
            1,
            accuracy: 0.0001
        )
    }

    func testScrollChevronsFollowTheDirectionOfEachPreview() {
        let fullyOpaque = SettingsForm.opacityChevronState(
            at: Date(timeIntervalSinceReferenceDate: 0)
        )
        let fullyDimmed = SettingsForm.opacityChevronState(
            at: Date(timeIntervalSinceReferenceDate: 4)
        )
        let restoringOpacity = SettingsForm.opacityChevronState(
            at: Date(timeIntervalSinceReferenceDate: 6)
        )

        XCTAssertEqual(fullyOpaque.travelOffset, 0, accuracy: 0.0001)
        XCTAssertTrue(fullyOpaque.pointsDown)
        XCTAssertEqual(fullyOpaque.directionTransitionOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(fullyDimmed.travelOffset, 60, accuracy: 0.0001)
        XCTAssertFalse(fullyDimmed.pointsDown)
        XCTAssertEqual(fullyDimmed.directionTransitionOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(restoringOpacity.travelOffset, 30, accuracy: 0.0001)
        XCTAssertFalse(restoringOpacity.pointsDown)
        XCTAssertEqual(restoringOpacity.directionTransitionOpacity, 1, accuracy: 0.0001)

        let converging = SettingsForm.gatherChevronState(
            at: Date(timeIntervalSinceReferenceDate: 1.25)
        )
        let restoringPositions = SettingsForm.gatherChevronState(
            at: Date(timeIntervalSinceReferenceDate: 3.75)
        )

        XCTAssertEqual(converging.travelOffset, 30, accuracy: 0.0001)
        XCTAssertTrue(converging.pointsDown)
        XCTAssertEqual(converging.directionTransitionOpacity, 1, accuracy: 0.0001)
        XCTAssertEqual(restoringPositions.travelOffset, 30, accuracy: 0.0001)
        XCTAssertFalse(restoringPositions.pointsDown)
        XCTAssertEqual(restoringPositions.directionTransitionOpacity, 1, accuracy: 0.0001)
    }

    func testScrollChevronsFadeOutAndBackInAroundDirectionChanges() {
        let beforeOpacityReversal = SettingsForm.opacityChevronState(
            at: Date(timeIntervalSinceReferenceDate: 3.825)
        )
        let atOpacityReversal = SettingsForm.opacityChevronState(
            at: Date(timeIntervalSinceReferenceDate: 4)
        )
        let afterOpacityReversal = SettingsForm.opacityChevronState(
            at: Date(timeIntervalSinceReferenceDate: 4.175)
        )

        XCTAssertEqual(beforeOpacityReversal.directionTransitionOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(atOpacityReversal.directionTransitionOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(afterOpacityReversal.directionTransitionOpacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(beforeOpacityReversal.pointsDown)
        XCTAssertFalse(afterOpacityReversal.pointsDown)

        let beforeGatherReversal = SettingsForm.gatherChevronState(
            at: Date(timeIntervalSinceReferenceDate: 2.825)
        )
        let atGatherReversal = SettingsForm.gatherChevronState(
            at: Date(timeIntervalSinceReferenceDate: 3)
        )
        let afterGatherReversal = SettingsForm.gatherChevronState(
            at: Date(timeIntervalSinceReferenceDate: 3.175)
        )

        XCTAssertEqual(beforeGatherReversal.directionTransitionOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(atGatherReversal.directionTransitionOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(afterGatherReversal.directionTransitionOpacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(beforeGatherReversal.pointsDown)
        XCTAssertFalse(afterGatherReversal.pointsDown)
    }

    func testSixScrollChevronsWrapOnlyWhileTransparentAtTheEdges() {
        XCTAssertEqual(ScrollChevronLayout.count, 6)
        XCTAssertEqual(
            240 - ScrollChevronLayout.previewCenterX - ScrollChevronLayout.indicatorWidth / 2,
            4,
            accuracy: 0.0001
        )
        XCTAssertEqual(ScrollChevronLayout.opacity(at: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(ScrollChevronLayout.opacity(at: 30), 0, accuracy: 0.0001)
        XCTAssertEqual(ScrollChevronLayout.opacity(at: -30), 0, accuracy: 0.0001)

        let leavingBottom = ScrollChevronLayout.verticalOffset(
            for: 5,
            travelOffset: 4.999
        )
        let enteringTop = ScrollChevronLayout.verticalOffset(
            for: 5,
            travelOffset: 5.001
        )
        XCTAssertEqual(leavingBottom, 29.999, accuracy: 0.0001)
        XCTAssertEqual(enteringTop, -29.999, accuracy: 0.0001)
        XCTAssertLessThan(ScrollChevronLayout.opacity(at: leavingBottom), 0.0001)
        XCTAssertLessThan(ScrollChevronLayout.opacity(at: enteringTop), 0.0001)
    }

    func testLineUpPreviewSortsMockNotesLikeScreenWindowsForEveryCorner() {
        let starts = [
            CGPoint(x: 42, y: 39),
            CGPoint(x: 121, y: 88),
            CGPoint(x: 193, y: 48),
        ]

        XCTAssertEqual(
            LineUpPreviewLayout.orderedIndices(
                in: starts,
                alignment: .horizontal,
                corner: .bottomLeft
            ),
            [0, 1, 2]
        )
        XCTAssertEqual(
            LineUpPreviewLayout.orderedIndices(
                in: starts,
                alignment: .horizontal,
                corner: .bottomRight
            ),
            [2, 1, 0]
        )
        XCTAssertEqual(
            LineUpPreviewLayout.orderedIndices(
                in: starts,
                alignment: .vertical,
                corner: .bottomLeft
            ),
            [1, 2, 0]
        )
        XCTAssertEqual(
            LineUpPreviewLayout.orderedIndices(
                in: starts,
                alignment: .vertical,
                corner: .topLeft
            ),
            [0, 2, 1]
        )
    }

    func testBottomRightGatherPreviewMovesScrollChevronsToTheLeftEdge() {
        XCTAssertEqual(
            ScrollChevronLayout.previewCenterX(for: .bottomRight)
                - ScrollChevronLayout.indicatorWidth / 2,
            4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            240 - ScrollChevronLayout.previewCenterX(for: .topRight)
                - ScrollChevronLayout.indicatorWidth / 2,
            4,
            accuracy: 0.0001
        )
    }

    func testOpacityShortcutReservesShiftForAllNotes() {
        let configured = AppShortcuts.opacity(
            from: Int(NSEvent.ModifierFlags([.option, .shift]).rawValue)
        )

        XCTAssertEqual(configured.modifiers, [.option])
        XCTAssertTrue(AppShortcuts.opacityShortcut(configured, matches: [.option]))
        XCTAssertTrue(AppShortcuts.opacityShortcut(configured, matches: [.option, .shift]))
        XCTAssertFalse(AppShortcuts.opacityShortcut(configured, matches: [.option, .control]))
    }

    func testConfigurableShortcutsPreserveKeyAndModifierChoices() {
        let gather = AppShortcuts.gather(from: Int(NSEvent.ModifierFlags([.option, .shift]).rawValue))
        let lineUp = AppShortcuts.lineUp(
            key: "L",
            modifiersRawValue: Int(NSEvent.ModifierFlags([.command, .option]).rawValue)
        )

        XCTAssertTrue(gather.matches([.option, .shift]))
        XCTAssertFalse(gather.matches([.option]))
        XCTAssertEqual(lineUp.key, "l")
        XCTAssertEqual(lineUp.modifiers, [.command, .option])
        XCTAssertEqual(lineUp.displayName, "⌥⌘L")
    }

    func testNoteWindowBackgroundStaysAtConfiguredOpacityUntilWindowCrossesIt() {
        XCTAssertEqual(
            NoteWindowBackground.tintAlpha(configuredAlpha: 0.6, windowAlpha: 1),
            0.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NoteWindowBackground.tintAlpha(configuredAlpha: 0.6, windowAlpha: 0.8) * 0.8,
            0.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NoteWindowBackground.tintAlpha(configuredAlpha: 0.6, windowAlpha: 0.4) * 0.4,
            0.4,
            accuracy: 0.0001
        )
    }

    func testAllNoteOpacityDecreaseStartsAtMostOpaqueWindow() {
        XCTAssertEqual(
            NoteWindowOpacity.adjustedAlphas([1, 0.8, 0.4], by: -0.1),
            [0.9, 0.8, 0.4]
        )
        XCTAssertEqual(
            NoteWindowOpacity.adjustedAlphas([1, 0.8, 0.4], by: -0.3),
            [0.7, 0.7, 0.4]
        )
    }

    func testAllNoteOpacityIncreaseStartsAtLeastOpaqueWindow() {
        let firstStep = NoteWindowOpacity.adjustedAlphas([0.2, 0.5, 0.9], by: 0.1)
        XCTAssertEqual(firstStep[0], 0.3, accuracy: 0.0001)
        XCTAssertEqual(firstStep[1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(firstStep[2], 0.9, accuracy: 0.0001)

        let crossingStep = NoteWindowOpacity.adjustedAlphas([0.2, 0.5, 0.9], by: 0.4)
        XCTAssertEqual(crossingStep[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(crossingStep[1], 0.6, accuracy: 0.0001)
        XCTAssertEqual(crossingStep[2], 0.9, accuracy: 0.0001)
    }

    func testPerNoteWindowOpacityIsInstallationLocalAndClamped() throws {
        let suiteName = "NoteWindowOpacityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let noteID = NoteID()

        XCTAssertEqual(NoteWindowOpacity.currentAlpha(for: noteID, defaults: defaults), 1)
        NoteWindowOpacity.setAlpha(0, for: noteID, defaults: defaults)
        XCTAssertEqual(NoteWindowOpacity.currentAlpha(for: noteID, defaults: defaults), 0.1)
        NoteWindowOpacity.setAlpha(2, for: noteID, defaults: defaults)
        XCTAssertEqual(NoteWindowOpacity.currentAlpha(for: noteID, defaults: defaults), 1)
    }

    func testClickThroughNotesAllowsCommandClickToInteract() {
        XCTAssertFalse(NoteWindowClickThrough.shouldIgnoreMouseEvents(
            isEnabled: false,
            isCommandPressed: false
        ))
        XCTAssertTrue(NoteWindowClickThrough.shouldIgnoreMouseEvents(
            isEnabled: true,
            isCommandPressed: false
        ))
        XCTAssertFalse(NoteWindowClickThrough.shouldIgnoreMouseEvents(
            isEnabled: true,
            isCommandPressed: true
        ))
    }

    func testClickThroughRequiresSeventyPercentBackgroundTransparency() {
        XCTAssertFalse(NoteWindowClickThrough.isAvailable(backgroundTransparency: 0.6999))
        XCTAssertTrue(NoteWindowClickThrough.isAvailable(backgroundTransparency: 0.7))
        XCTAssertTrue(NoteWindowClickThrough.isAvailable(backgroundTransparency: 1))

        XCTAssertTrue(SettingsForm.crossesClickThroughThreshold(from: 0.69, to: 0.7))
        XCTAssertTrue(SettingsForm.crossesClickThroughThreshold(from: 0.7, to: 0.69))
        XCTAssertFalse(SettingsForm.crossesClickThroughThreshold(from: 0.7, to: 0.8))
        XCTAssertFalse(SettingsForm.crossesClickThroughThreshold(from: 0.5, to: 0.6))
    }

    func testClickThroughHoverHalvesWindowOpacity() {
        XCTAssertEqual(
            NoteWindowClickThrough.hoverAlpha(for: 0.8, isHovered: true),
            0.4
        )
        XCTAssertEqual(
            NoteWindowClickThrough.hoverAlpha(for: 0.8, isHovered: false),
            0.8
        )
    }

    func testFocusBlurRevealsOnHoverOnlyWhenClickThroughIsDisabled() {
        XCTAssertFalse(Note.shouldBlurContent(
            isFocusBlurred: true,
            isClickThroughEnabled: false,
            isHovering: true,
            isCommandInteractionActive: false
        ))
        XCTAssertTrue(Note.shouldBlurContent(
            isFocusBlurred: true,
            isClickThroughEnabled: true,
            isHovering: true,
            isCommandInteractionActive: false
        ))
        XCTAssertFalse(Note.shouldBlurContent(
            isFocusBlurred: true,
            isClickThroughEnabled: true,
            isHovering: true,
            isCommandInteractionActive: true
        ))
    }

    func testWheelOpacityUsesPhysicalDirectionRegardlessOfNaturalScrollingPreference() {
        XCTAssertEqual(
            NoteWindowOpacity.wheelDelta(
                verticalDelta: 1,
                isDirectionInvertedFromDevice: false,
                isPrecise: false
            ),
            0.05
        )
        XCTAssertEqual(
            NoteWindowOpacity.wheelDelta(
                verticalDelta: -1,
                isDirectionInvertedFromDevice: true,
                isPrecise: false
            ),
            0.05
        )
    }

    func testShiftCommandWheelUsesHorizontalDeltaRemappedByMacOS() {
        XCTAssertEqual(
            NoteWindowOpacity.wheelDelta(
                verticalDelta: 0,
                horizontalDelta: -1,
                usesShiftAxis: true,
                isDirectionInvertedFromDevice: false,
                isPrecise: false
            ),
            -0.05
        )
        XCTAssertNil(NoteWindowOpacity.wheelDelta(
            verticalDelta: 0,
            horizontalDelta: -1,
            usesShiftAxis: false,
            isDirectionInvertedFromDevice: false,
            isPrecise: false
        ))
    }

    func testCornerConvergenceMovesEveryNoteByTheSameProgressAndReturnsToItsStart() throws {
        let farID = NoteID()
        let nearID = NoteID()
        let items = [
            NoteCornerConvergence.Item(
                noteID: farID,
                startFrame: NSRect(x: 700, y: 500, width: 200, height: 200),
                pendingTaskCount: 5
            ),
            NoteCornerConvergence.Item(
                noteID: nearID,
                startFrame: NSRect(x: 300, y: 250, width: 200, height: 200),
                pendingTaskCount: 1
            )
        ]
        let targets = NoteCornerConvergence.targetFrames(
            for: items,
            in: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            corner: .bottomLeft,
            margin: 40
        )
        var convergence = NoteCornerConvergence(
            startFrames: Dictionary(uniqueKeysWithValues: items.map { ($0.noteID, $0.startFrame) }),
            targetFrames: targets
        )

        let initialWheelUpFrames = convergence.frames(afterWheelDelta: 0.05)
        XCTAssertEqual(convergence.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(initialWheelUpFrames[farID], items[0].startFrame)
        XCTAssertEqual(initialWheelUpFrames[nearID], items[1].startFrame)

        var halfway: [NoteID: NSRect] = [:]
        for _ in 0..<10 {
            halfway = convergence.frames(afterWheelDelta: -0.05)
        }
        XCTAssertEqual(convergence.progress, 0.5, accuracy: 0.0001)
        let farHalfwayFrame = try XCTUnwrap(halfway[farID])
        let nearHalfwayFrame = try XCTUnwrap(halfway[nearID])
        XCTAssertEqual(farHalfwayFrame.minX, 370, accuracy: 0.0001)
        XCTAssertEqual(nearHalfwayFrame.minX, 175, accuracy: 0.0001)
        XCTAssertGreaterThan(700 - farHalfwayFrame.minX, 300 - nearHalfwayFrame.minX)

        var restored: [NoteID: NSRect] = [:]
        for _ in 0..<20 {
            restored = convergence.frames(afterWheelDelta: 0.05)
        }
        XCTAssertEqual(convergence.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(restored[farID], items[0].startFrame)
        XCTAssertEqual(restored[nearID], items[1].startFrame)
    }

    func testCornerConvergenceKeepsMarginAndStaggersTargets() throws {
        let mostPendingID = NoteID()
        let leastPendingID = NoteID()
        let items = [
            NoteCornerConvergence.Item(
                noteID: leastPendingID,
                startFrame: NSRect(x: 100, y: 100, width: 200, height: 150),
                pendingTaskCount: 1
            ),
            NoteCornerConvergence.Item(
                noteID: mostPendingID,
                startFrame: NSRect(x: 200, y: 200, width: 200, height: 150),
                pendingTaskCount: 8
            )
        ]

        let targets = NoteCornerConvergence.targetFrames(
            for: items,
            in: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            corner: .topRight,
            margin: 40
        )
        let backTarget = try XCTUnwrap(targets[mostPendingID])
        let frontTarget = try XCTUnwrap(targets[leastPendingID])
        XCTAssertEqual(backTarget.origin, NSPoint(x: 760, y: 610))
        XCTAssertEqual(frontTarget.origin, NSPoint(x: 750, y: 600))
    }

    func testCornerConvergenceKeepsFullNotesInsideThePhysicalScreen() throws {
        let leftNoteID = NoteID()
        let leftTargets = NoteCornerConvergence.targetFrames(
            for: [NoteCornerConvergence.Item(
                noteID: leftNoteID,
                startFrame: NSRect(x: -100, y: 300, width: 200, height: 100),
                pendingTaskCount: 0
            )],
            in: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            corner: .bottomLeft,
            margin: 40
        )
        let leftTarget = try XCTUnwrap(leftTargets[leftNoteID])
        XCTAssertEqual(leftTarget.minX, 0, accuracy: 0.0001)

        let rightNoteID = NoteID()
        let rightTargets = NoteCornerConvergence.targetFrames(
            for: [NoteCornerConvergence.Item(
                noteID: rightNoteID,
                startFrame: NSRect(x: 1_100, y: 300, width: 200, height: 100),
                pendingTaskCount: 0
            )],
            in: NSRect(x: 0, y: 0, width: 1_000, height: 800),
            corner: .bottomRight,
            margin: 40
        )
        let rightTarget = try XCTUnwrap(rightTargets[rightNoteID])
        XCTAssertEqual(rightTarget.maxX, 1_000, accuracy: 0.0001)
    }

    func testDesktopPlacementUsesThePhysicalScreenEdges() {
        let screenFrame = NSRect(x: -1_400, y: 0, width: 1_360, height: 860)
        let windowSize = NSSize(width: 200, height: 100)

        XCTAssertEqual(
            MacDesktopPlacement.origin(
                for: windowSize,
                on: screenFrame,
                corner: .topRight,
                horizontal: true,
                position: 40,
                cornerMargin: 40
            ),
            NSPoint(x: -280, y: 720)
        )
        XCTAssertEqual(
            MacDesktopPlacement.origin(
                for: windowSize,
                on: screenFrame,
                corner: .bottomLeft,
                horizontal: true,
                position: 40,
                cornerMargin: 40
            ),
            NSPoint(x: -1_360, y: 40)
        )
    }

    func testCornerConvergenceZOrderKeepsHoveredNoteFrontmost() {
        let mostPendingID = NoteID()
        let middleID = NoteID()
        let hoveredID = NoteID()
        let items = [
            NoteCornerConvergence.Item(noteID: hoveredID, startFrame: .zero, pendingTaskCount: 10),
            NoteCornerConvergence.Item(noteID: middleID, startFrame: .zero, pendingTaskCount: 3),
            NoteCornerConvergence.Item(noteID: mostPendingID, startFrame: .zero, pendingTaskCount: 7)
        ]

        XCTAssertEqual(
            NoteCornerConvergence.orderedBackToFront(items, hoveredNoteID: hoveredID).map(\.noteID),
            [mostPendingID, middleID, hoveredID]
        )
    }

    func testCornerConvergenceZOrderPutsSmallerNotesInFrontOfLargerNotes() {
        let largeHoveredID = NoteID()
        let mediumID = NoteID()
        let smallID = NoteID()
        let items = [
            NoteCornerConvergence.Item(
                noteID: smallID,
                startFrame: NSRect(x: 0, y: 0, width: 140, height: 120),
                pendingTaskCount: 20
            ),
            NoteCornerConvergence.Item(
                noteID: largeHoveredID,
                startFrame: NSRect(x: 0, y: 0, width: 320, height: 260),
                pendingTaskCount: 0
            ),
            NoteCornerConvergence.Item(
                noteID: mediumID,
                startFrame: NSRect(x: 0, y: 0, width: 220, height: 180),
                pendingTaskCount: 10
            )
        ]

        XCTAssertEqual(
            NoteCornerConvergence.orderedBackToFront(
                items,
                hoveredNoteID: largeHoveredID
            ).map(\.noteID),
            [largeHoveredID, mediumID, smallID]
        )
    }

    func testCornerConvergenceCanInferCornerProgressAndRecoverStoredStartFrames() throws {
        let noteID = NoteID()
        let startFrame = NSRect(x: 700, y: 500, width: 200, height: 200)
        let targetFrame = NSRect(x: 40, y: 40, width: 200, height: 200)
        var convergence = NoteCornerConvergence(
            startFrames: [noteID: startFrame],
            targetFrames: [noteID: targetFrame],
            currentFrames: [noteID: targetFrame]
        )

        XCTAssertEqual(convergence.progress, 1, accuracy: 0.0001)
        for _ in 0..<20 {
            _ = convergence.frames(afterWheelDelta: 0.05)
        }
        XCTAssertEqual(convergence.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(convergence.frames[noteID]), startFrame)
    }

    func testCornerConvergenceRetargetsToChangedSettingWithoutLosingProgress() throws {
        let noteID = NoteID()
        let startFrame = NSRect(x: 400, y: 300, width: 200, height: 200)
        var convergence = NoteCornerConvergence(
            startFrames: [noteID: startFrame],
            targetFrames: [noteID: NSRect(x: 40, y: 40, width: 200, height: 200)]
        )
        for _ in 0..<10 {
            _ = convergence.frames(afterWheelDelta: -0.05)
        }

        let retargeted = convergence.retargeted(
            to: [noteID: NSRect(x: 760, y: 560, width: 200, height: 200)]
        )

        XCTAssertEqual(retargeted.progress, 0.5, accuracy: 0.0001)
        let frame = try XCTUnwrap(retargeted.frames[noteID])
        XCTAssertEqual(frame.origin.x, 580, accuracy: 0.0001)
        XCTAssertEqual(frame.origin.y, 430, accuracy: 0.0001)
        XCTAssertEqual(retargeted.startFrames[noteID], startFrame)
    }

    func testCornerScrollSessionKeepsMovingAfterNotesLeavePointerUntilModifiersAreReleased() {
        let firstNoteID = NoteID()
        let secondNoteID = NoteID()
        var session = NoteCornerConvergence.ScrollSession()

        XCTAssertNil(session.noteID(currentlyHovered: nil))
        XCTAssertEqual(session.noteID(currentlyHovered: firstNoteID), firstNoteID)
        XCTAssertEqual(session.noteID(currentlyHovered: nil), firstNoteID)
        XCTAssertEqual(session.noteID(currentlyHovered: secondNoteID), secondNoteID)

        session.update(modifiers: [.command, .control, .shift])
        XCTAssertEqual(session.noteID(currentlyHovered: nil), secondNoteID)

        session.update(modifiers: [.command])
        XCTAssertNil(session.noteID(currentlyHovered: nil))
    }

    func testCornerScrollSessionUsesTheConfiguredModifiers() {
        let noteID = NoteID()
        var session = NoteCornerConvergence.ScrollSession()

        XCTAssertEqual(session.noteID(currentlyHovered: noteID), noteID)
        session.update(modifiers: [.option, .shift], requiredModifiers: [.option])
        XCTAssertEqual(session.noteID(currentlyHovered: nil), noteID)
        session.update(modifiers: [.shift], requiredModifiers: [.option])
        XCTAssertNil(session.noteID(currentlyHovered: nil))
    }

    func testManualNotePositionPersistsAndWheelMovementDoesNotReplaceIt() throws {
        let suiteName = "NoteWindowManualPositionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let noteID = NoteID()
        let draggedOrigin = NSPoint(x: 321, y: 654)

        NoteWindowManualPosition.ensureStoredOrigin(draggedOrigin, for: noteID, defaults: defaults)
        NoteWindowManualPosition.setIsWheelPosition(true, for: noteID, defaults: defaults)
        NoteWindowManualPosition.ensureStoredOrigin(
            NSPoint(x: 999, y: 999),
            for: noteID,
            defaults: defaults
        )

        XCTAssertEqual(NoteWindowManualPosition.storedOrigin(for: noteID, defaults: defaults), draggedOrigin)
        XCTAssertTrue(NoteWindowManualPosition.isWheelPosition(for: noteID, defaults: defaults))

        let laterDraggedOrigin = NSPoint(x: 111, y: 222)
        NoteWindowManualPosition.recordDraggedOrigin(laterDraggedOrigin, for: noteID, defaults: defaults)
        XCTAssertEqual(NoteWindowManualPosition.storedOrigin(for: noteID, defaults: defaults), laterDraggedOrigin)
        XCTAssertFalse(NoteWindowManualPosition.isWheelPosition(for: noteID, defaults: defaults))
        XCTAssertTrue(NoteWindowManualPosition.shouldRecordDrag(pressedMouseButtons: 1))
        XCTAssertFalse(NoteWindowManualPosition.shouldRecordDrag(pressedMouseButtons: 0))
    }

    func testConvergedNoteUsesManualDragOriginOnNextLaunch() throws {
        let suiteName = "NoteWindowLaunchPositionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let noteID = NoteID()
        let manualOrigin = NSPoint(x: 180, y: 420)
        let convergedAutosaveOrigin = NSPoint(x: 20, y: 20)
        NoteWindowManualPosition.recordDraggedOrigin(
            manualOrigin,
            for: noteID,
            defaults: defaults
        )
        NoteWindowManualPosition.setIsWheelPosition(true, for: noteID, defaults: defaults)

        let launchOrigin = NoteWindowManualPosition.launchOrigin(
            restoredOrigin: convergedAutosaveOrigin,
            for: noteID,
            defaults: defaults
        )

        XCTAssertEqual(launchOrigin, manualOrigin)
        XCTAssertFalse(NoteWindowManualPosition.isWheelPosition(for: noteID, defaults: defaults))
        XCTAssertEqual(NoteWindowManualPosition.storedOrigin(for: noteID, defaults: defaults), manualOrigin)
    }

    @MainActor
    func testMacTransportIsDisabledUnderTests() {
        XCTAssertFalse(MacSharedStoreBootstrapper.transportEnabledByDefault)
    }

    @MainActor
    func testMenuBarAttentionImageKeepsTildoneIconAndAddsBadge() throws {
        let active = try XCTUnwrap(MenuBarController.menuBarImage(
            for: .active,
            accessibilityDescription: "Tildone"
        ))
        let attention = try XCTUnwrap(MenuBarController.menuBarImage(
            for: .attentionNeeded,
            accessibilityDescription: "iCloud sync needs attention"
        ))

        XCTAssertEqual(active.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(attention.size, NSSize(width: 18, height: 18))
        XCTAssertNotEqual(active.tiffRepresentation, attention.tiffRepresentation)
        XCTAssertTrue(active.isTemplate)
        XCTAssertTrue(attention.isTemplate)
    }

    @MainActor
    func testMacNoteSyncIndicatorDistinguishesLocalChoiceAndAttention() {
        XCTAssertEqual(MacNoteTitlebarLayout.titleTrailingInset, 60)
        XCTAssertGreaterThan(
            MacNoteTitlebarLayout.titleTrailingInset,
            MacNoteTitlebarLayout.trailingMargin
                + MacNoteTitlebarLayout.colorPickerWidth
                + MacNoteTitlebarLayout.controlSpacing
                + MacNoteTitlebarLayout.syncIndicatorWidth
        )
        XCTAssertEqual(MacNoteSyncIndicatorState.resolve(
            isUsingNotesOnMacByChoice: false,
            syncNeedsAttention: false
        ), .hidden)
        XCTAssertEqual(MacNoteSyncIndicatorState.resolve(
            isUsingNotesOnMacByChoice: true,
            syncNeedsAttention: false
        ), .onlyOnThisMac)
        XCTAssertEqual(MacNoteSyncIndicatorState.resolve(
            isUsingNotesOnMacByChoice: true,
            syncNeedsAttention: true
        ), .attentionNeeded)

        let localControl = MacNoteSyncTitlebarControl(state: .onlyOnThisMac)
        let localStatus = String(localized: "Only on this Mac — not syncing with iPhone or iCloud.")
        XCTAssertEqual(localControl.toolTip, localStatus)
        XCTAssertEqual(localControl.accessibilityLabel(), localStatus)
        XCTAssertEqual(localControl.accessibilityRole(), .button)
        XCTAssertTrue(localControl.acceptsFirstMouse(for: nil))
        XCTAssertFalse(localControl.mouseDownCanMoveWindow)

        let opensOptions = expectation(
            forNotification: .openSyncResolutionOptions,
            object: nil
        )
        XCTAssertTrue(localControl.accessibilityPerformPress())
        wait(for: [opensOptions], timeout: 1)

        let attentionControl = MacNoteSyncTitlebarControl(state: .attentionNeeded)
        let attentionStatus = String(localized: "Not syncing with iCloud right now. Your notes are safe on this Mac.")
        XCTAssertEqual(MacNoteSyncIndicatorState.attentionNeeded.symbolName, "exclamationmark.icloud")
        XCTAssertNotNil(NSImage(
            systemSymbolName: MacNoteSyncIndicatorState.attentionNeeded.symbolName,
            accessibilityDescription: attentionStatus
        ))
        XCTAssertEqual(attentionControl.toolTip, attentionStatus)
        XCTAssertEqual(attentionControl.accessibilityLabel(), attentionStatus)
        XCTAssertEqual(attentionControl.accessibilityRole(), .button)

        let opensStatus = expectation(forNotification: .openSyncStatus, object: nil)
        XCTAssertTrue(attentionControl.accessibilityPerformPress())
        wait(for: [opensStatus], timeout: 1)
    }

    @MainActor
    func testMacNoteTitlebarControlsRemainClickableWhileWindowIsInactive() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 14, height: 16))
        button.style()
        XCTAssertTrue(button.hitTest(NSPoint(x: 7, y: 8)) === button)

        let restore = MinimizedNoteRestoreTitlebarControl(onRestore: {})
        XCTAssertTrue(restore.acceptsFirstMouse(for: nil))
        XCTAssertFalse(restore.mouseDownCanMoveWindow)
    }

    @MainActor
    func testWindowAccessorRestoresButtonActionsAfterViewRefreshAndReconstruction() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let contentView = try XCTUnwrap(window.contentView)
        let minimizeButton = try XCTUnwrap(window.standardWindowButton(.miniaturizeButton))
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        var minimizeCount = 0
        var closeCount = 0

        let attachmentView = WindowAccessorAttachmentView()
        attachmentView.update(
            onMinimize: { minimizeCount += 1 },
            onClose: { closeCount += 1 }
        )
        contentView.addSubview(attachmentView)

        XCTAssertTrue(minimizeButton.isEnabled)
        XCTAssertTrue(minimizeButton.target is NoteWindowButtonActionController)
        XCTAssertTrue(closeButton.target is NoteWindowButtonActionController)
        minimizeButton.performClick(nil)
        closeButton.performClick(nil)
        XCTAssertEqual(minimizeCount, 1)
        XCTAssertEqual(closeCount, 1)

        minimizeButton.isEnabled = false
        minimizeButton.target = nil
        minimizeButton.action = nil
        attachmentView.update(
            onMinimize: { minimizeCount += 10 },
            onClose: { closeCount += 10 }
        )

        XCTAssertTrue(minimizeButton.isEnabled)
        XCTAssertTrue(minimizeButton.target is NoteWindowButtonActionController)
        minimizeButton.performClick(nil)
        XCTAssertEqual(minimizeCount, 11)

        minimizeButton.isEnabled = false
        minimizeButton.target = nil
        minimizeButton.action = nil

        let replacementView = WindowAccessorAttachmentView()
        replacementView.update(
            onMinimize: { minimizeCount += 100 },
            onClose: { closeCount += 100 }
        )
        contentView.addSubview(replacementView)
        attachmentView.reset()
        attachmentView.removeFromSuperview()

        XCTAssertTrue(minimizeButton.isEnabled)
        XCTAssertTrue(minimizeButton.target is NoteWindowButtonActionController)
        minimizeButton.performClick(nil)
        XCTAssertEqual(minimizeCount, 111)
    }

    func testMinimizedRestoreControlUsesTheFullTitlebarHeight() {
        let pickerFrame = NSRect(x: 220, y: 272, width: 26, height: 22)
        let frame = MacNoteTitlebarLayout.minimizedRestoreFrame(
            in: NSRect(x: 0, y: 0, width: 250, height: 300),
            alignedWith: pickerFrame
        )

        XCTAssertEqual(frame, NSRect(x: 229, y: 272, width: 19, height: 22))
    }

    func testRepeatedMinimizeAllKeepsTheFirstNormalFrameAndRestoresOnce() throws {
        let normalFrame = NSRect(x: 120, y: 180, width: 420, height: 360)
        let compactFrame = NSRect(x: 20, y: 20, width: 96, height: 98)
        var state = NoteWindowMinimizationState()

        XCTAssertTrue(state.beginMinimizing(
            from: normalFrame,
            autosaveName: "note-frame"
        ))
        XCTAssertFalse(state.beginMinimizing(
            from: compactFrame,
            autosaveName: "note-frame"
        ))

        let restoration = try XCTUnwrap(state.beginRestoring())
        XCTAssertEqual(restoration.frame, normalFrame)
        XCTAssertEqual(restoration.autosaveName, "note-frame")
        XCTAssertFalse(state.isMinimized)
        XCTAssertTrue(state.isRestoring)
        XCTAssertNil(state.beginRestoring())
        XCTAssertFalse(state.beginMinimizing(
            from: compactFrame,
            autosaveName: "note-frame"
        ))

        state.finishRestoring()
        XCTAssertFalse(state.isMinimized)
        XCTAssertFalse(state.isRestoring)
    }

    func testPreviouslyPersistedCompactFrameIsRepairedAtTheSameTopLeftPosition() {
        let compactFrame = NSRect(x: 20, y: 300, width: 96, height: 98)
        let repairedFrame = MacNoteWindowGeometry.repairingUndersizedRestoredFrame(
            compactFrame,
            minimumSize: NSSize(width: 180, height: 272),
            defaultSize: NSSize(width: 250, height: 332)
        )

        XCTAssertEqual(repairedFrame, NSRect(x: 20, y: 66, width: 250, height: 332))
        XCTAssertEqual(repairedFrame.maxY, compactFrame.maxY)
    }

    @MainActor
    func testQuittingWhileMinimizedLeavesTheNormalFrameForRelaunch() throws {
        let autosaveName = "TildoneTests.NoteWindowFrame.\(UUID().uuidString)"
        NSWindow.removeFrame(usingName: autosaveName)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let normalFrame = NSRect(
            x: visibleFrame.minX + 100,
            y: visibleFrame.minY + 100,
            width: 420,
            height: 360
        )
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.setFrame(normalFrame, display: false)
        XCTAssertTrue(window.setFrameAutosaveName(autosaveName))
        let savedNormalFrame = window.frameDescriptor

        XCTAssertEqual(NoteWindowFrameAutosavePolicy.suspend(for: window), autosaveName)
        XCTAssertEqual(window.frameAutosaveName, NoteWindowFrameAutosavePolicy.disabledName)
        window.setFrame(NSRect(x: 20, y: 20, width: 96, height: 98), display: false)

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)"),
            savedNormalFrame
        )
    }

    @MainActor
    func testRestoringReenablesAutosaveForTheFullFrame() {
        let autosaveName = "TildoneTests.NoteWindowRestore.\(UUID().uuidString)"
        NSWindow.removeFrame(usingName: autosaveName)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let normalFrame = NSRect(x: 140, y: 180, width: 400, height: 340)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.setFrame(normalFrame, display: false)
        XCTAssertTrue(window.setFrameAutosaveName(autosaveName))
        NoteWindowFrameAutosavePolicy.suspend(for: window)
        window.setFrame(NSRect(x: 20, y: 20, width: 96, height: 98), display: false)

        window.setFrame(normalFrame, display: false)
        NoteWindowFrameAutosavePolicy.resume(for: window, using: autosaveName)

        XCTAssertEqual(window.frameAutosaveName, autosaveName)
        XCTAssertEqual(window.frame, normalFrame)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)"),
            window.frameDescriptor
        )
    }

    func testMacRemoteRefreshPropagatesMigrationAndReloadFailures() async {
        enum FixtureError: Error, Equatable { case migration, reload }
        var reloadAttempted = false
        do {
            try await MacRemoteRefreshHandler.run(
                migrateColors: { throw FixtureError.migration },
                reloadSnapshots: { reloadAttempted = true }
            )
            XCTFail("Expected migration failure")
        } catch {
            XCTAssertEqual(error as? FixtureError, .migration)
            XCTAssertFalse(reloadAttempted)
        }

        do {
            try await MacRemoteRefreshHandler.run(
                migrateColors: {},
                reloadSnapshots: { throw FixtureError.reload }
            )
            XCTFail("Expected reload failure")
        } catch {
            XCTAssertEqual(error as? FixtureError, .reload)
        }
    }

    func testMacSyncPresentationDistinguishesActivePausedAndAttention() {
        let active = SyncStatus(availability: .available, activity: .idle)
        XCTAssertEqual(MacSyncPresentation.state(
            status: active,
            transportState: .active,
            enabledByDefault: true,
            hasUnadoptedLocalWorkspace: false
        ), .active)
        XCTAssertEqual(MacSyncPresentation.state(
            status: active,
            transportState: .paused,
            enabledByDefault: true,
            hasUnadoptedLocalWorkspace: false
        ), .paused)

        let zoneReset = SyncStatus(
            availability: .zoneResetRequired,
            activity: .attentionNeeded,
            issue: .zoneReset
        )
        XCTAssertEqual(MacSyncPresentation.state(
            status: zoneReset,
            transportState: .paused,
            enabledByDefault: true,
            hasUnadoptedLocalWorkspace: false
        ), .attentionNeeded)
        XCTAssertEqual(
            MacSyncPresentation.symbol(for: .attentionNeeded),
            "exclamationmark.triangle.fill"
        )
        XCTAssertEqual(
            MacSyncPresentation.menuBarBadgeSymbol(for: .attentionNeeded),
            "exclamationmark.circle.fill"
        )
        XCTAssertNil(MacSyncPresentation.menuBarBadgeSymbol(for: .active))
        XCTAssertNil(MacSyncPresentation.menuBarBadgeSymbol(for: .paused))
        XCTAssertNil(MacSyncPresentation.menuBarBadgeSymbol(for: .disabled))
        let resetDetail = MacSyncPresentation.detail(
            status: zoneReset,
            state: .attentionNeeded,
            hasUnadoptedLocalWorkspace: false,
            canAdoptLocalWorkspace: false,
            isUsingNotesOnMacByChoice: false
        )
        XCTAssertTrue(resetDetail.contains("will not rebuild or upload"))

        let conflictDetail = MacSyncPresentation.detail(
            status: active,
            state: .attentionNeeded,
            hasUnadoptedLocalWorkspace: true,
            canAdoptLocalWorkspace: false,
            isUsingNotesOnMacByChoice: false
        )
        let localChoiceDetail = MacSyncPresentation.detail(
            status: .disabled,
            state: .disabled,
            hasUnadoptedLocalWorkspace: false,
            canAdoptLocalWorkspace: false,
            isUsingNotesOnMacByChoice: true
        )
        XCTAssertTrue(localChoiceDetail.contains("notes saved on this Mac"))
        XCTAssertTrue(localChoiceDetail.contains("iCloud are unchanged"))
        for detail in [resetDetail, conflictDetail, localChoiceDetail] {
            for jargon in ["workspace", "zone", "reseed", "CloudKit", "transport"] {
                XCTAssertFalse(detail.localizedCaseInsensitiveContains(jargon), detail)
            }
        }
    }

    func testMacRecoveryUIRequiresAdoptionConfirmationAndHasNoAutomaticResetHatch() throws {
        XCTAssertFalse(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: true,
            explicitChoice: nil
        ))
        XCTAssertTrue(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: false,
            explicitChoice: nil
        ))
        XCTAssertFalse(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: false,
            explicitChoice: .thisMac
        ))
        XCTAssertTrue(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: true,
            explicitChoice: .iCloud
        ))
        XCTAssertTrue(MacWorkspaceSelectionPolicy.canAdoptLocalWorkspace(
            localNeedsAdoption: true,
            accountHasContent: false
        ))
        XCTAssertFalse(MacWorkspaceSelectionPolicy.canAdoptLocalWorkspace(
            localNeedsAdoption: true,
            accountHasContent: true
        ))

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try [
            "Tildone/App/Lifecycle/TildoneApp.swift",
            "Tildone/Views/App/Sync/MacSyncStatusView.swift",
            "Tildone/Views/App/Resolution/MacNoteResolutionOptions.swift",
            "Tildone/App/Lifecycle/MenuBarController.swift",
        ].map {
            try String(contentsOf: sourceURL.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")
        let storeSource = try String(
            contentsOf: sourceURL.appendingPathComponent("Tildone/Store/Bootstrap/MacSharedStoreBootstrapper.swift"),
            encoding: .utf8
        )
        let desktopSource = try String(
            contentsOf: sourceURL.appendingPathComponent("Tildone/Views/Desktop.swift"),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: sourceURL.appendingPathComponent("Tildone/Views/Note/Core/Note+Content.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(appSource.contains(".alert(\"Copy notes to iCloud?\""))
        XCTAssertTrue(appSource.contains("Review Options…"))
        XCTAssertTrue(appSource.contains("Combine Notes — Recommended"))
        XCTAssertTrue(appSource.contains("MacNoteResolutionOptions("))
        XCTAssertTrue(appSource.contains("RoundedRectangle(cornerRadius: 8"))
        XCTAssertTrue(appSource.contains("resolveNotesAfterConfirmation(action)"))
        XCTAssertFalse(appSource.contains(".sheet(isPresented: $showsResolutionOptions)"))
        XCTAssertTrue(appSource.contains(".id(ObjectIdentifier(store))"))
        XCTAssertTrue(appSource.contains("noteSyncIndicatorState: noteSyncIndicatorState"))
        XCTAssertTrue(appSource.contains("syncNeedsAttention: displayState == .attentionNeeded"))
        XCTAssertTrue(appSource.contains("publisher(for: .openSyncResolutionOptions)"))
        XCTAssertTrue(appSource.contains("These notes won’t appear on your iPhone or in iCloud. You can combine them later."))
        XCTAssertTrue(desktopSource.contains("guard noteSyncIndicatorState != .hidden else { return }"))
        XCTAssertTrue(desktopSource.contains("picker.frame.minX - indicatorSize.width - MacNoteTitlebarLayout.controlSpacing"))
        XCTAssertTrue(desktopSource.contains(".onChange(of: noteSyncIndicatorState)"))
        XCTAssertTrue(desktopSource.contains("setNoteSyncIndicatorState(state)"))
        XCTAssertTrue(noteSource.contains(".padding(.trailing, MacNoteTitlebarLayout.titleTrailingInset)"))
        XCTAssertTrue(storeSource.contains("revalidateAccount(workspaceID:"))
        XCTAssertTrue(storeSource.contains("didJustChooseNotesOnMac = true"))
        XCTAssertTrue(storeSource.contains("func dismissNotesOnMacNotice()"))
        XCTAssertTrue(appSource.contains("setAccessibilityValue(title)"))
        XCTAssertTrue(appSource.contains("button.image = Self.menuBarImage(for: state"))
        XCTAssertFalse(storeSource.contains("TILDONE_ALLOW_LOCAL_WORKSPACE_ADOPTION"))
        XCTAssertFalse(storeSource.contains("TILDONE_RESET_DEVELOPMENT_ACCOUNT_WORKSPACE"))
        XCTAssertFalse(storeSource.contains("resetDevelopmentAccountWorkspace"))
    }

    func testMacNoteLocationChoicePersistsPerAccountAndIgnoresMalformedValues() throws {
        let suiteName = "MacNoteLocationChoiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let firstAccount = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondAccount = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let store = MacNoteLocationChoiceStore(defaults: defaults)

        XCTAssertNil(store.choice(for: firstAccount))
        XCTAssertNil(store.choice(for: secondAccount))
        store.set(.thisMac, for: firstAccount)

        let relaunchedStore = MacNoteLocationChoiceStore(defaults: defaults)
        XCTAssertEqual(relaunchedStore.choice(for: firstAccount), .thisMac)
        XCTAssertNil(relaunchedStore.choice(for: secondAccount))

        defaults.set(
            "unexpected",
            forKey: "noteLocationChoice.\(secondAccount.uuidString.lowercased())"
        )
        XCTAssertNil(relaunchedStore.choice(for: secondAccount))
    }

    func testCombineNotesPreservesLocalSourceAndQueuesCombinedAccountContent() async throws {
        let local = try TildoneRepository(
            descriptor: .inMemory(workspace: .localOnly),
            replicaID: ReplicaID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        )
        let account = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID())),
            replicaID: ReplicaID(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        )
        let localNoteID = NoteID(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!)
        let accountNoteID = NoteID(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!)
        let localTaskID = TaskID(UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!)
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)

        _ = try await local.createNote(id: localNoteID, createdAt: createdAt, title: "Local")
        _ = try await local.addTask(
            id: localTaskID,
            to: localNoteID,
            createdAt: createdAt,
            text: "Local task",
            orderToken: try OrderToken(rawValue: "h")
        )
        _ = try await account.createNote(
            id: accountNoteID,
            createdAt: createdAt,
            title: "iCloud"
        )
        let localNotesBefore = try await local.allSyncNotes()
        let localTasksBefore = try await local.allSyncTasks()

        let fingerprint = try await MacNoteResolutionService.combine(
            localRepository: local,
            accountRepository: account,
            at: createdAt.addingTimeInterval(1)
        )

        let localNotesAfter = try await local.allSyncNotes()
        let localTasksAfter = try await local.allSyncTasks()
        let localFingerprintAfter = try await MacNoteResolutionService.fingerprint(repository: local)
        let accountNotes = try await account.allSyncNotes()
        let accountTasks = try await account.allSyncTasks()
        let accountPending = try await account.pendingMutations()

        XCTAssertEqual(localNotesAfter, localNotesBefore)
        XCTAssertEqual(localTasksAfter, localTasksBefore)
        XCTAssertEqual(fingerprint, localFingerprintAfter)
        XCTAssertEqual(
            Set(accountNotes.map(\.id)),
            [localNoteID, accountNoteID]
        )
        XCTAssertEqual(accountTasks.map(\.id), [localTaskID])
        XCTAssertEqual(
            Set(accountPending.map(\.targetStableID)),
            [localNoteID.stringValue, accountNoteID.stringValue, localTaskID.stringValue]
        )
    }

    func testTrackedAppSchemesUseDeterministicDebugLaunchAndReleaseArchiveConfigurations() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in ["Tildone", "Tildone iOS"] {
            let schemeURL = repositoryRoot
                .appendingPathComponent("Tildone.xcodeproj/xcshareddata/xcschemes")
                .appendingPathComponent("\(name).xcscheme")
            let source = try String(contentsOf: schemeURL, encoding: .utf8)
            XCTAssertTrue(source.contains("<LaunchAction\n      buildConfiguration = \"Debug\""), name)
            XCTAssertTrue(source.contains("<ArchiveAction\n      buildConfiguration = \"Release\""), name)
            XCTAssertFalse(source.contains("language ="), name)
        }
    }

    func testCheckboxDoesNotRetainParentOwnedCompletionAsLocalState() {
        let storedPropertyNames = Set(
            Mirror(reflecting: Checkbox(checked: false)).children.compactMap(\.label)
        )

        XCTAssertTrue(
            storedPropertyNames.contains("checked"),
            "Completion must remain an ordinary parent-owned view input."
        )
        XCTAssertFalse(
            storedPropertyNames.contains("_checked"),
            "Duplicating completion in @State prevents remote parent updates from redrawing the checkbox."
        )
    }

    @MainActor
    func testPrimarySceneUsesSingleUniqueCoordinatorWindow() {
        let scene = TildonePrimaryScene { EmptyView() }
        let bodyType = String(reflecting: type(of: scene.body))

        XCTAssertTrue(
            bodyType.contains("SwiftUI.Window<"),
            "The process-wide note-window coordinator must use SwiftUI.Window."
        )
        XCTAssertFalse(
            bodyType.contains("SwiftUI.WindowGroup<"),
            "WindowGroup permits multiple coordinator instances on macOS."
        )
    }

    func testMacSharedStoreRoutesCRUDThroughDomainRepository() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: ReplicaID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let store = await MainActor.run { MacSharedStore(repository: repository) }

        let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        try await store.renameNote(note.id, to: "Title")
        try await store.setColor(.purple, for: note.id)
        let last = try await store.addTask(to: note.id, text: "Last")
        let first = try await store.addTask(to: note.id, text: "First", insertingAt: 0)
        try await store.setTaskCompletion(first.id, completed: true)
        try await store.editTask(last.id, text: "Changed")

        let loadedSnapshot = await MainActor.run { store.note(note.id) }
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(snapshot.title, "Title")
        XCTAssertEqual(snapshot.color, .purple)
        XCTAssertEqual(snapshot.tasks.map(\.text), ["First", "Changed"])
        XCTAssertEqual(snapshot.pendingTasks.map(\.id), [last.id])

        try await store.deleteTask(first.id)
        try await store.deleteTask(last.id)
        try await store.renameNote(note.id, to: nil)
        let loadedEmpty = await MainActor.run { store.note(note.id) }
        let empty = try XCTUnwrap(loadedEmpty)
        XCTAssertTrue(empty.isDeletable)
        try await store.deleteNote(note.id)
        let remaining = try await repository.visibleNotes()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testLegacyMacColorLookupPrefersPerNoteValueAndPreservesGlobalFallback() throws {
        let suiteName = "TildoneColorMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let coloredNote = NoteID()
        let fallbackNote = NoteID()
        defaults.set(NoteColor.orange.legacyRawValue, forKey: NoteColor.storageKey)
        defaults.set(
            NoteColor.pink.legacyRawValue,
            forKey: NoteColor.storageKey(for: coloredNote)
        )

        XCTAssertEqual(NoteColor.legacyLocalColor(for: coloredNote, defaults: defaults), .pink)
        XCTAssertNil(NoteColor.legacyLocalColor(for: fallbackNote, defaults: defaults))
        XCTAssertEqual(NoteColor.current(from: defaults), .orange)
    }

    func testMacSharedStoreRemovesRestoredEmptyNotesButKeepsCompletedNotesForFade() async throws {
        let repository = try TildoneRepository(descriptor: .inMemory())
        let store = await MainActor.run { MacSharedStore(repository: repository) }
        let empty = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        let completed = try await store.createNote(createdAt: Date(timeIntervalSince1970: 200))
        let task = try await store.addTask(to: completed.id, text: "Complete me")
        try await store.setTaskCompletion(task.id, completed: true)

        try await store.prepareForPresentation()

        let snapshots = await MainActor.run { store.notes }
        XCTAssertNil(snapshots.first(where: { $0.id == empty.id }))
        let restoredCompletion = try XCTUnwrap(snapshots.first(where: { $0.id == completed.id }))
        XCTAssertTrue(restoredCompletion.isComplete)
        XCTAssertNotNil(restoredCompletion.completedAt)
    }

    func testCompletionFadeLifecycleResumesUsingPersistedCompletionDate() {
        let completedAt = Date(timeIntervalSince1970: 100)
        var lifecycle = CompletionFadeLifecycle()

        lifecycle.synchronize(completedAt: completedAt)

        XCTAssertTrue(lifecycle.isFading)
        XCTAssertTrue(lifecycle.showsCompletionOverlay)
        XCTAssertEqual(
            lifecycle.progress(at: Date(timeIntervalSince1970: 105), duration: 20),
            5
        )
        XCTAssertNil(lifecycle.beginDeletionIfReady(
            at: Date(timeIntervalSince1970: 119.9),
            duration: 20
        ))
        XCTAssertEqual(lifecycle.beginDeletionIfReady(
            at: Date(timeIntervalSince1970: 120),
            duration: 20
        ), completedAt)
        XCTAssertFalse(lifecycle.isFading)
        XCTAssertTrue(lifecycle.showsCompletionOverlay)
    }

    func testCompletionFadeCancellationOnlyAppliesToCurrentCompletionCycle() {
        let firstCompletion = Date(timeIntervalSince1970: 100)
        let secondCompletion = Date(timeIntervalSince1970: 200)
        var lifecycle = CompletionFadeLifecycle()

        lifecycle.synchronize(completedAt: firstCompletion)
        lifecycle.cancel()
        lifecycle.synchronize(completedAt: firstCompletion)

        XCTAssertEqual(lifecycle.phase, .cancelled(completedAt: firstCompletion))
        XCTAssertFalse(lifecycle.showsCompletionOverlay)

        lifecycle.synchronize(completedAt: nil)
        XCTAssertEqual(lifecycle.phase, .idle)

        lifecycle.synchronize(completedAt: secondCompletion)
        XCTAssertEqual(lifecycle.phase, .fading(completedAt: secondCompletion))
        XCTAssertTrue(lifecycle.showsCompletionOverlay)
    }

    func testCompletionFadeRestoresCancelledAutoDeletionState() {
        let completedAt = Date(timeIntervalSince1970: 100)
        var lifecycle = CompletionFadeLifecycle()

        lifecycle.synchronize(completedAt: completedAt, autoDeletionCancelled: true)

        XCTAssertEqual(lifecycle.phase, .cancelled(completedAt: completedAt))
        XCTAssertFalse(lifecycle.showsCompletionOverlay)
        XCTAssertNil(lifecycle.beginDeletionIfReady(
            at: Date(timeIntervalSince1970: 200),
            duration: 20
        ))
    }

    func testCompletionFadeProgressClampsAcrossSleepAndClockSkew() {
        var lifecycle = CompletionFadeLifecycle()
        lifecycle.synchronize(completedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(
            lifecycle.progress(at: Date(timeIntervalSince1970: 90), duration: 20),
            0
        )
        XCTAssertEqual(
            lifecycle.progress(at: Date(timeIntervalSince1970: 1_000), duration: 20),
            20
        )
    }

    func testMacSharedStoreReordersBeginningMiddleAndEndWithoutChangingTaskContent() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildoneMacReorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        let descriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: baseDirectory,
            workspace: .localOnly
        )
        let replica = ReplicaID(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let noteID: NoteID
        let taskIDs: [TaskID]
        var expectedContent: [TaskID: TildoneDomain.Task] = [:]

        do {
            let repository = try TildoneRepository(
                descriptor: descriptor,
                replicaID: replica,
                now: { Date(timeIntervalSince1970: 4_000) }
            )
            let store = await MainActor.run { MacSharedStore(repository: repository) }
            let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
            noteID = note.id

            let first = try await store.addTask(
                to: note.id, text: "First", createdAt: Date(timeIntervalSince1970: 101)
            )
            let second = try await store.addTask(
                to: note.id, text: "Second", createdAt: Date(timeIntervalSince1970: 102)
            )
            let third = try await store.addTask(
                to: note.id, text: "Third", createdAt: Date(timeIntervalSince1970: 103)
            )
            let fourth = try await store.addTask(
                to: note.id, text: "Fourth", createdAt: Date(timeIntervalSince1970: 104)
            )
            try await store.setTaskCompletion(second.id, completed: true)
            taskIDs = [first.id, second.id, third.id, fourth.id]
            expectedContent = Dictionary(
                uniqueKeysWithValues: try await repository.orderedTasks(in: note.id).map { ($0.id, $0) }
            )
            try await repository.acknowledgeMutations(
                ids: Set(try await repository.pendingMutations().map(\.id))
            )

            let movedToBeginning = try await store.moveTask(fourth.id, in: note.id, to: 0)
            let beginningIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToBeginning)
            XCTAssertEqual(beginningIDs, [fourth.id, first.id, second.id, third.id])

            let movedToMiddle = try await store.moveTask(fourth.id, in: note.id, to: 3)
            let middleIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToMiddle)
            XCTAssertEqual(middleIDs, [first.id, second.id, fourth.id, third.id])

            let movedToEnd = try await store.moveTask(first.id, in: note.id, to: 4)
            let endIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToEnd)
            XCTAssertEqual(endIDs, [second.id, fourth.id, third.id, first.id])

            let pendingBeforeNoOp = try await repository.pendingMutations()
            let noOpMoved = try await store.moveTask(fourth.id, in: note.id, to: 1)
            let pendingAfterNoOp = try await repository.pendingMutations()
            XCTAssertFalse(noOpMoved)
            XCTAssertEqual(pendingAfterNoOp, pendingBeforeNoOp)

            let finalTasks = try await repository.orderedTasks(in: note.id)
            XCTAssertEqual(finalTasks.map(\.id), [second.id, fourth.id, third.id, first.id])
            XCTAssertEqual(Set(finalTasks.map(\.id)), Set(taskIDs))
            XCTAssertEqual(finalTasks.count, taskIDs.count)
            for task in finalTasks {
                let original = try XCTUnwrap(expectedContent[task.id])
                XCTAssertEqual(task.noteID, original.noteID)
                XCTAssertEqual(task.createdAt, original.createdAt)
                XCTAssertEqual(task.text, original.text)
                XCTAssertEqual(task.textVersion, original.textVersion)
                XCTAssertEqual(task.completion, original.completion)
                XCTAssertEqual(task.completionVersion, original.completionVersion)
                XCTAssertEqual(task.lifecycle, original.lifecycle)
                XCTAssertEqual(task.lifecycleVersion, original.lifecycleVersion)
            }
            XCTAssertEqual(
                finalTasks.first(where: { $0.id == second.id })?.orderToken,
                expectedContent[second.id]?.orderToken
            )
            XCTAssertEqual(
                finalTasks.first(where: { $0.id == third.id })?.orderToken,
                expectedContent[third.id]?.orderToken
            )

            let pending = try await repository.pendingMutations()
            XCTAssertEqual(pending.count, 3)
            XCTAssertEqual(Set(pending.map(\.targetKind)), [.note, .task])
            XCTAssertEqual(
                Set(pending.map(\.targetStableID)),
                [note.id.stringValue, first.id.stringValue, fourth.id.stringValue]
            )
        }

        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let persisted = try await reopened.orderedTasks(in: noteID)
        XCTAssertEqual(persisted.map(\.id), [taskIDs[1], taskIDs[3], taskIDs[2], taskIDs[0]])
        XCTAssertEqual(Set(persisted.map(\.id)), Set(taskIDs))
        XCTAssertEqual(persisted.count, taskIDs.count)
        for task in persisted {
            let original = try XCTUnwrap(expectedContent[task.id])
            XCTAssertEqual(task.noteID, original.noteID)
            XCTAssertEqual(task.createdAt, original.createdAt)
            XCTAssertEqual(task.text, original.text)
            XCTAssertEqual(task.completion, original.completion)
            XCTAssertEqual(task.lifecycle, original.lifecycle)
        }
        let durablePending = try await reopened.pendingMutations()
        XCTAssertEqual(
            Set(durablePending.map(\.targetStableID)),
            [noteID.stringValue, taskIDs[0].stringValue, taskIDs[3].stringValue]
        )
    }

    func testMacSharedStoreMovesNewlyCompletedTaskToEndWhenEnabled() async throws {
        CompletedTaskOrderPreference.clearOriginalOrderTokens()
        addTeardownBlock { CompletedTaskOrderPreference.clearOriginalOrderTokens() }

        let repository = try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: ReplicaID(),
            now: { Date(timeIntervalSince1970: 4_000) }
        )
        let store = await MainActor.run { MacSharedStore(repository: repository) }
        let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        let first = try await store.addTask(to: note.id, text: "First")
        let second = try await store.addTask(to: note.id, text: "Second")
        let third = try await store.addTask(to: note.id, text: "Third")

        try await store.setTaskCompletion(
            second.id,
            completed: true,
            moveToEndWhenCompleted: true
        )

        let completedOrder = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(completedOrder.map(\.id), [first.id, third.id, second.id])
        XCTAssertTrue(completedOrder.last?.isCompleted == true)

        try await store.setTaskCompletion(
            first.id,
            completed: true,
            moveToEndWhenCompleted: true
        )
        let orderedCompletedTasks = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(orderedCompletedTasks.map(\.id), [third.id, first.id, second.id])

        try await store.setTaskCompletion(
            first.id,
            completed: false,
            moveToEndWhenCompleted: true
        )
        try await store.setTaskCompletion(
            second.id,
            completed: false,
            moveToEndWhenCompleted: true
        )
        let incompleteOrder = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(
            incompleteOrder.map(\.id),
            [first.id, second.id, third.id]
        )

        try await store.setTaskCompletion(
            second.id,
            completed: true,
            moveToEndWhenCompleted: true
        )
        try await store.applyCompletedTaskOrdering(enabled: false)
        let restoredOrder = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restoredOrder.map(\.id), [first.id, second.id, third.id])
    }

    func testMacSharedStoreRegroupsExistingCompletedTasksAndRestoresTheirPositions() async throws {
        CompletedTaskOrderPreference.clearOriginalOrderTokens()
        addTeardownBlock { CompletedTaskOrderPreference.clearOriginalOrderTokens() }

        let repository = try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: ReplicaID(),
            now: { Date(timeIntervalSince1970: 4_000) }
        )
        let store = await MainActor.run { MacSharedStore(repository: repository) }
        let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        let first = try await store.addTask(to: note.id, text: "First")
        let second = try await store.addTask(to: note.id, text: "Second")
        let third = try await store.addTask(to: note.id, text: "Third")
        let fourth = try await store.addTask(to: note.id, text: "Fourth")
        try await store.setTaskCompletion(second.id, completed: true)
        try await store.setTaskCompletion(fourth.id, completed: true)

        try await store.applyCompletedTaskOrdering(enabled: true)
        let groupedTasks = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(groupedTasks.map(\.id), [first.id, third.id, second.id, fourth.id])

        try await store.applyCompletedTaskOrdering(enabled: false)
        let restoredTasks = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restoredTasks.map(\.id), [first.id, second.id, third.id, fourth.id])
    }

    func testMacTaskDragPayloadRejectsCrossNoteAndMalformedDrops() throws {
        let noteID = NoteID()
        let taskID = TaskID()
        let payload = MacTaskDragPayload(noteID: noteID, taskID: taskID)

        XCTAssertTrue(payload.isValid(for: noteID, taskIDs: [taskID]))
        XCTAssertFalse(payload.isValid(for: NoteID(), taskIDs: [taskID]))
        XCTAssertFalse(payload.isValid(for: noteID, taskIDs: [TaskID()]))
        XCTAssertThrowsError(try JSONDecoder().decode(
            MacTaskDragPayload.self,
            from: Data(#"{"noteID":"invalid","taskID":"invalid"}"#.utf8)
        ))
    }

    func testMacTaskRowsExposeDedicatedDragHandlesAndDropTargets() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try [
            "Tildone/Views/Note/Tasks/MacTaskDragPayload.swift",
            "Tildone/Views/Note/Tasks/TaskRow.swift",
            "Tildone/Views/Note/Tasks/TaskReorderDropTarget.swift",
            "Tildone/Views/Note/Tasks/TaskReorderFeedback.swift",
            "Tildone/Views/Note/Tasks/TaskReorderHandle.swift",
            "Tildone/Views/Note/Tasks/TaskReorderPreview.swift",
        ].map {
            try String(contentsOf: sourceRoot.appendingPathComponent($0), encoding: .utf8)
        }.joined(separator: "\n")

        XCTAssertTrue(source.contains("TaskReorderHandle("))
        XCTAssertTrue(source.contains(".draggable(payload)"))
        XCTAssertTrue(source.contains("CodableRepresentation(contentType: .json)"))
        XCTAssertTrue(source.contains("TaskReorderPreview("))
        XCTAssertTrue(source.contains("Checkbox(checked: isCompleted)"))
        XCTAssertTrue(source.contains(
            "Text(taskText.isEmpty ? String(localized: \"Untitled task\") : taskText)"
        ))
        XCTAssertTrue(source.contains(".padding(.top, dropPlacement == .before"))
        XCTAssertTrue(source.contains(".padding(.bottom, dropPlacement == .after"))
        XCTAssertTrue(source.contains("? TaskReorderFeedback.expandedHeight"))
        XCTAssertTrue(source.contains("TaskReorderInsertionLine()"))
        XCTAssertTrue(source.contains(".onChange(of: feedbackResetToken)"))
        XCTAssertTrue(source.contains(".padding(.trailing, 8)"))
        XCTAssertFalse(source.contains(".stroke(Color.accentColor"))
        XCTAssertTrue(source.contains(".dropDestination(for: MacTaskDragPayload.self)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Reorder task\")"))
    }

    /// Opt-in smoke test hosted by the signed development Mac app so the test
    /// inherits the real CloudKit entitlement. The normal suite is fully local.
    func testDevelopmentCloudKitRoundTripWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TILDONE_RUN_DEVELOPMENT_CLOUDKIT_TESTS"] == "1" else {
            throw XCTSkip("Development CloudKit integration is explicitly opt-in")
        }
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw XCTSkip("A development iCloud account is required")
        }

        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: TildoneCloudSchema.zoneID)
        let zoneResults = try await database.modifyRecordZones(saving: [zone], deleting: [])
        _ = try zoneResults.saveResults[TildoneCloudSchema.zoneID]?.get()

        let timestamp = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stamp = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
        let note = Note(
            id: NoteID(),
            createdAt: timestamp,
            title: "Stage 8 synthetic integration record",
            titleVersion: stamp,
            lifecycleVersion: stamp,
            lastMeaningfulEditAt: timestamp,
            lastMeaningfulEditVersion: stamp
        )
        let mapper = CloudKitRecordMapper()
        let record = mapper.record(from: .note(note))
        do {
            let saved = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            _ = try saved.saveResults[record.recordID]?.get()
            let fetched = try await database.records(for: [record.recordID])
            let fetchedRecord = try XCTUnwrap(fetched[record.recordID]).get()
            XCTAssertEqual(try mapper.syncRecord(from: fetchedRecord), .note(note))
            _ = try await database.modifyRecords(saving: [], deleting: [record.recordID])
        } catch {
            _ = try? await database.modifyRecords(saving: [], deleting: [record.recordID])
            throw error
        }
    }
}
