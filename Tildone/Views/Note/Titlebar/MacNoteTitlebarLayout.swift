//
//  MacNoteTitlebarLayout.swift
//  Tildone
//

import AppKit

enum MacNoteTitlebarLayout {
    static let stickyHeaderHeight: CGFloat = 30
    static let titleLeadingInset: CGFloat = 82
    static let trailingMargin: CGFloat = 3.5
    static let colorPickerTopMargin: CGFloat = 4.8
    static let colorPickerWidth: CGFloat = 24
    static let formatControlWidth: CGFloat = 22
    static let kindControlWidth: CGFloat = 22
    static let focusPrivacyControlWidth: CGFloat = 22
    static let minimizedRestoreWidth: CGFloat = 19
    static let syncIndicatorWidth: CGFloat = 22
    static let controlHeight: CGFloat = 22
    static let controlSpacing: CGFloat = 2
    static let titleControlSpacing: CGFloat = 6
    static let syncIndicatorTrailingSpacing: CGFloat = 8

    // Reserve the cloud slot even when hidden so status changes cannot overlap
    // the title or shift the remaining controls.
    static var accessoryWidth: CGFloat {
        trailingMargin + colorPickerWidth + formatControlWidth
            + controlSpacing + 2 + focusPrivacyControlWidth
            + controlSpacing + kindControlWidth
            + syncIndicatorTrailingSpacing + syncIndicatorWidth
    }

    static var titleTrailingInset: CGFloat {
        accessoryWidth + titleControlSpacing
    }

    static func colorPickerFrame(in bounds: NSRect) -> NSRect {
        return NSRect(
            x: bounds.maxX - colorPickerWidth - trailingMargin,
            // Match AppKit’s autoresizing rounding so a status refresh keeps
            // the picker and explicitly positioned controls on the same center.
            y: (bounds.maxY - controlHeight - colorPickerTopMargin).rounded(),
            width: colorPickerWidth,
            height: controlHeight
        )
    }

    static func syncIndicatorFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        NSRect(
            x: kindControlFrame(alignedWith: pickerFrame).minX - syncIndicatorTrailingSpacing - syncIndicatorWidth,
            y: pickerFrame.midY - controlHeight / 2,
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
        let focusPrivacyFrame = focusPrivacyControlFrame(alignedWith: pickerFrame)
        return NSRect(
            x: focusPrivacyFrame.minX - kindControlWidth - controlSpacing,
            y: pickerFrame.midY - 1,
            width: kindControlWidth,
            height: controlHeight
        )
    }

    static func focusPrivacyControlFrame(alignedWith pickerFrame: NSRect) -> NSRect {
        let formatFrame = formatControlFrame(alignedWith: pickerFrame)
        return NSRect(
            x: formatFrame.minX - focusPrivacyControlWidth - controlSpacing - 2,
            y: pickerFrame.midY - 1,
            width: focusPrivacyControlWidth,
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
