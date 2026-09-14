//
//  MacNoteTitlebarLayout.swift
//  Tildone
//

import AppKit

enum MacNoteTitlebarLayout {
    static let titleLeadingInset: CGFloat = 82
    static let trailingMargin: CGFloat = 3.5
    static let colorPickerTopMargin: CGFloat = 4.8
    static let colorPickerWidth: CGFloat = 24
    static let formatControlWidth: CGFloat = 22
    static let kindControlWidth: CGFloat = 22
    static let minimizedRestoreWidth: CGFloat = 19
    static let syncIndicatorWidth: CGFloat = 22
    static let controlHeight: CGFloat = 22
    static let controlSpacing: CGFloat = 2
    static let titleControlSpacing: CGFloat = 6

    static var accessoryWidth: CGFloat {
        trailingMargin + colorPickerWidth
            + controlSpacing + formatControlWidth + controlSpacing + kindControlWidth
    }

    static var titleTrailingInset: CGFloat {
        accessoryWidth + titleControlSpacing
    }

    static func colorPickerFrame(in bounds: NSRect) -> NSRect {
        return NSRect(
            x: bounds.maxX - colorPickerWidth - trailingMargin,
            y: bounds.maxY - controlHeight - colorPickerTopMargin,
            width: colorPickerWidth,
            height: controlHeight
        )
    }

    static func syncIndicatorFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: kindControlFrame(alignedWith: pickerFrame).minX - controlSpacing - syncIndicatorWidth,
            y: pickerFrame.midY - 1,
            width: syncIndicatorWidth,
            height: controlHeight
        )
    }

    static func formatControlFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: pickerFrame.minX - formatControlWidth,
            y: pickerFrame.midY - 1,
            width: formatControlWidth,
            height: controlHeight
        )
    }

    static func kindControlFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        let formatFrame = formatControlFrame(alignedWith: pickerFrame)
        return NSRect(
            x: formatFrame.minX - kindControlWidth - controlSpacing,
            y: pickerFrame.midY - 1,
            width: kindControlWidth,
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
