//
//  TaskReorderFeedback.swift
//  Tildone
//

import SwiftUI

enum TaskReorderFeedback {
    static let restingHeight: CGFloat = 6
    static let insertionSpacing: CGFloat = 18
    static let expandedHeight = restingHeight + insertionSpacing
    static let animation = Animation.easeInOut(duration: 0.16)
}
