//
//  MacNoteTitlebarLayout.swift
//  Tildone
//

import AppKit

enum MacNoteTitlebarLayout {
    static let titleLeadingInset: CGFloat = 78
    static let trailingMargin: CGFloat = 2
    static let colorPickerWidth: CGFloat = 26
    static let minimizedRestoreWidth: CGFloat = 19
    static let syncIndicatorWidth: CGFloat = 24
    static let controlHeight: CGFloat = 22
    static let controlSpacing: CGFloat = 2
    static let titleControlSpacing: CGFloat = 6

    static var titleTrailingInset: CGFloat {
        trailingMargin + colorPickerWidth + controlSpacing + syncIndicatorWidth + titleControlSpacing
    }

    static func minimizedRestoreFrame(in bounds: NSRect, alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: bounds.maxX - minimizedRestoreWidth - trailingMargin,
            y: bounds.maxY - pickerFrame.height - 8,
            width: minimizedRestoreWidth,
            height: pickerFrame.height
        )
    }
}
