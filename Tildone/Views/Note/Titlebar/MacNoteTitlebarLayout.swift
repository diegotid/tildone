//
//  MacNoteTitlebarLayout.swift
//  Tildone
//

import AppKit

enum MacNoteTitlebarLayout {
    static let titleLeadingInset: CGFloat = 82
    static let trailingMargin: CGFloat = 3
    static let colorPickerWidth: CGFloat = 26
    static let formatControlWidth: CGFloat = 24
    static let colorPickerTopMargin: CGFloat = 5
    static let minimizedRestoreWidth: CGFloat = 19
    static let syncIndicatorWidth: CGFloat = 24
    static let controlHeight: CGFloat = 22
    static let controlSpacing: CGFloat = 2
    static let titleControlSpacing: CGFloat = 6

    static var accessoryWidth: CGFloat {
        trailingMargin + colorPickerWidth + controlSpacing + formatControlWidth
            + controlSpacing + syncIndicatorWidth
    }

    static var titleTrailingInset: CGFloat {
        accessoryWidth + titleControlSpacing
    }

    static func colorPickerFrame(in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.maxX - colorPickerWidth - trailingMargin,
            y: bounds.maxY - controlHeight - colorPickerTopMargin,
            width: colorPickerWidth,
            height: controlHeight
        )
    }

    static func syncIndicatorFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: pickerFrame.minX - formatControlWidth - 2 * controlSpacing - syncIndicatorWidth,
            y: pickerFrame.minY,
            width: syncIndicatorWidth,
            height: controlHeight
        )
    }

    static func formatControlFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: pickerFrame.minX - formatControlWidth - controlSpacing,
            y: pickerFrame.midY - 0.5,
            width: formatControlWidth,
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
