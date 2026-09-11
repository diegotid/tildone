//
//  MacNoteTitlebarLayout.swift
//  Tildone
//

import AppKit

enum MacNoteTitlebarLayout {
    static let titleLeadingInset: CGFloat = 82
    static let trailingMargin: CGFloat = 4
    static let colorPickerWidth: CGFloat = 24
    static let formatControlWidth: CGFloat = 22
    static let kindControlWidth: CGFloat = 22
    static let singleTaskCheckboxWidth: CGFloat = 22
    static let colorPickerTopMargin: CGFloat = 5
    static let minimizedRestoreWidth: CGFloat = 19
    static let syncIndicatorWidth: CGFloat = 22
    static let controlHeight: CGFloat = 22
    static let controlSpacing: CGFloat = 2
    static let titleControlSpacing: CGFloat = 6

    static func accessoryWidth(showsSingleTaskCheckbox: Bool) -> CGFloat {
        trailingMargin + colorPickerWidth
            + (showsSingleTaskCheckbox ? controlSpacing + singleTaskCheckboxWidth : 0)
            + controlSpacing + formatControlWidth + controlSpacing + kindControlWidth
    }

    static func titleTrailingInset(showsSingleTaskCheckbox: Bool) -> CGFloat {
        accessoryWidth(showsSingleTaskCheckbox: showsSingleTaskCheckbox) + titleControlSpacing
    }

    static var maximumTitleTrailingInset: CGFloat {
        titleTrailingInset(showsSingleTaskCheckbox: true)
    }

    static func colorPickerFrame(in bounds: NSRect, showsSingleTaskCheckbox: Bool) -> NSRect {
        let checkboxOffset = showsSingleTaskCheckbox
            ? singleTaskCheckboxWidth + controlSpacing
            : 0
        return NSRect(
            x: bounds.maxX - checkboxOffset - colorPickerWidth - trailingMargin,
            y: bounds.maxY - controlHeight - colorPickerTopMargin,
            width: colorPickerWidth,
            height: controlHeight
        )
    }

    static func syncIndicatorFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: kindControlFrame(alignedWith: pickerFrame).minX - controlSpacing - syncIndicatorWidth,
            y: pickerFrame.minY,
            width: syncIndicatorWidth,
            height: controlHeight
        )
    }

    static func formatControlFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: pickerFrame.minX - formatControlWidth,
            y: pickerFrame.minY,
            width: formatControlWidth,
            height: controlHeight
        )
    }

    static func kindControlFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        let formatFrame = formatControlFrame(alignedWith: pickerFrame)
        return NSRect(
            x: formatFrame.minX - kindControlWidth - controlSpacing,
            y: pickerFrame.minY,
            width: kindControlWidth,
            height: controlHeight
        )
    }

    static func singleTaskCheckboxFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: pickerFrame.maxX + controlSpacing,
            y: pickerFrame.minY,
            width: singleTaskCheckboxWidth,
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
