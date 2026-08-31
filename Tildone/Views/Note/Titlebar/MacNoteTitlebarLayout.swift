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

    static var accessoryWidth: CGFloat {
        trailingMargin + colorPickerWidth + controlSpacing + syncIndicatorWidth
    }

    static var titleTrailingInset: CGFloat {
        accessoryWidth + titleControlSpacing
    }

    static func colorPickerFrame(in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.maxX - colorPickerWidth - trailingMargin,
            y: max(bounds.minY, bounds.midY - controlHeight / 2 - 4),
            width: colorPickerWidth,
            height: controlHeight
        )
    }

    static func syncIndicatorFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: pickerFrame.minX - syncIndicatorWidth - controlSpacing,
            y: pickerFrame.minY,
            width: syncIndicatorWidth,
            height: controlHeight
        )
    }

    static func minimizedRestoreFrame(in bounds: NSRect, alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: bounds.maxX - minimizedRestoreWidth - trailingMargin,
            y: pickerFrame.minY,
            width: minimizedRestoreWidth,
            height: pickerFrame.height
        )
    }
}
