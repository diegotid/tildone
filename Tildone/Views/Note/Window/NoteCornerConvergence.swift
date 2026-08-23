//
//  NoteCornerConvergence.swift
//  Tildone
//

import AppKit
import TildoneDomain

struct NoteCornerConvergence {
    struct Item {
        let noteID: NoteID
        let startFrame: NSRect
        let pendingTaskCount: Int
    }

    struct ScrollSession {
        private(set) var hoveredNoteID: NoteID?

        mutating func noteID(currentlyHovered candidate: NoteID?) -> NoteID? {
            if let candidate {
                hoveredNoteID = candidate
            }
            return hoveredNoteID
        }

        mutating func update(modifiers: NSEvent.ModifierFlags) {
            guard modifiers.contains(.command), modifiers.contains(.control) else {
                hoveredNoteID = nil
                return
            }
        }
    }

    static let separation: CGFloat = 10

    let startFrames: [NoteID: NSRect]
    let targetFrames: [NoteID: NSRect]
    private(set) var progress: CGFloat = 0

    init(
        startFrames: [NoteID: NSRect],
        targetFrames: [NoteID: NSRect],
        currentFrames: [NoteID: NSRect]? = nil
    ) {
        self.startFrames = startFrames
        self.targetFrames = targetFrames
        if let currentFrames {
            progress = Self.inferredProgress(
                startFrames: startFrames,
                targetFrames: targetFrames,
                currentFrames: currentFrames
            )
        }
    }

    mutating func frames(afterWheelDelta wheelDelta: CGFloat) -> [NoteID: NSRect] {
        progress = min(max(progress - wheelDelta, 0), 1)
        return frames
    }

    func retargeted(to targetFrames: [NoteID: NSRect]) -> NoteCornerConvergence {
        var convergence = NoteCornerConvergence(
            startFrames: startFrames,
            targetFrames: targetFrames
        )
        convergence.progress = progress
        return convergence
    }

    var frames: [NoteID: NSRect] {
        startFrames.reduce(into: [:]) { result, entry in
            guard let target = targetFrames[entry.key] else {
                result[entry.key] = entry.value
                return
            }
            result[entry.key] = NSRect(
                x: entry.value.minX + (target.minX - entry.value.minX) * progress,
                y: entry.value.minY + (target.minY - entry.value.minY) * progress,
                width: entry.value.width,
                height: entry.value.height
            )
        }
    }

    static func targetFrames(
        for items: [Item],
        in screenFrame: NSRect,
        corner: ArrangementCorner,
        margin: CGFloat
    ) -> [NoteID: NSRect] {
        orderedBackToFront(items).enumerated().reduce(into: [:]) { result, entry in
            let (index, item) = entry
            let offset = CGFloat(index) * separation
            let targetsLeft = corner == .bottomLeft || corner == .topLeft
            let targetsBottom = corner == .bottomLeft || corner == .bottomRight
            let candidateX = targetsLeft
                ? screenFrame.minX + margin + offset
                : screenFrame.maxX - margin - item.startFrame.width - offset
            let candidateY = targetsBottom
                ? screenFrame.minY + margin + offset
                : screenFrame.maxY - margin - item.startFrame.height - offset

            // A note already closer to the selected corner stays there instead of
            // moving away from it to join the staggered stack.
            let preferredX = targetsLeft
                ? min(candidateX, item.startFrame.minX)
                : max(candidateX, item.startFrame.minX)
            let preferredY = targetsBottom
                ? min(candidateY, item.startFrame.minY)
                : max(candidateY, item.startFrame.minY)
            let minimumX = screenFrame.minX
            let maximumX = max(
                minimumX,
                screenFrame.maxX - item.startFrame.width
            )
            let minimumY = screenFrame.minY
            let maximumY = max(
                minimumY,
                screenFrame.maxY - item.startFrame.height
            )
            let targetX = min(max(preferredX, minimumX), maximumX)
            let targetY = min(max(preferredY, minimumY), maximumY)
            result[item.noteID] = NSRect(
                x: targetX,
                y: targetY,
                width: item.startFrame.width,
                height: item.startFrame.height
            )
        }
    }

    static func orderedBackToFront(_ items: [Item], hoveredNoteID: NoteID? = nil) -> [Item] {
        items.sorted { lhs, rhs in
            let lhsArea = lhs.startFrame.width * lhs.startFrame.height
            let rhsArea = rhs.startFrame.width * rhs.startFrame.height
            if lhsArea != rhsArea {
                return lhsArea > rhsArea
            }
            if lhs.noteID == hoveredNoteID { return false }
            if rhs.noteID == hoveredNoteID { return true }
            if lhs.pendingTaskCount != rhs.pendingTaskCount {
                return lhs.pendingTaskCount > rhs.pendingTaskCount
            }
            return lhs.noteID.stringValue < rhs.noteID.stringValue
        }
    }

    private static func inferredProgress(
        startFrames: [NoteID: NSRect],
        targetFrames: [NoteID: NSRect],
        currentFrames: [NoteID: NSRect]
    ) -> CGFloat {
        let progressValues = startFrames.compactMap { noteID, startFrame -> CGFloat? in
            guard let targetFrame = targetFrames[noteID], let currentFrame = currentFrames[noteID] else {
                return nil
            }
            let targetVector = CGVector(
                dx: targetFrame.minX - startFrame.minX,
                dy: targetFrame.minY - startFrame.minY
            )
            let squaredLength = targetVector.dx * targetVector.dx + targetVector.dy * targetVector.dy
            guard squaredLength > 0 else { return nil }
            let currentVector = CGVector(
                dx: currentFrame.minX - startFrame.minX,
                dy: currentFrame.minY - startFrame.minY
            )
            let projection = (
                currentVector.dx * targetVector.dx + currentVector.dy * targetVector.dy
            ) / squaredLength
            return min(max(projection, 0), 1)
        }
        guard !progressValues.isEmpty else { return 0 }
        return progressValues.reduce(0, +) / CGFloat(progressValues.count)
    }

}
