//
//  Checkbox.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import AppKit
import SwiftUI

struct Checkbox: View {
    var checked: Bool = false
    var size: CGFloat = Layout.checkboxSize

    var disabled: Bool = false
    var onToggle: (() -> Void)?

    private var checkSize: CGFloat {
        size * Layout.checkboxCheckSize / Layout.checkboxSize
    }

    var body: some View {
        return ZStack {
            ClickTarget(isEnabled: !disabled && onToggle != nil, isChecked: checked, onToggle: onToggle)
                .frame(width: size, height: size)
            Circle()
                .fill(Color(.checkboxOffFill))
                .overlay(Circle().stroke(self.checked ? .accentColor : Color(.checkboxBorder)))
                .frame(width: size, height: size, alignment: .center)
                .opacity(disabled ? 0.6 : 1)
                .allowsHitTesting(false)
            if self.checked {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: checkSize,
                           height: checkSize,
                           alignment: .center)
                    .allowsHitTesting(false)
            }
        }
    }

    private struct ClickTarget: NSViewRepresentable {
        let isEnabled: Bool
        let isChecked: Bool
        let onToggle: (() -> Void)?

        func makeNSView(context: Context) -> ClickControl {
            ClickControl()
        }

        func updateNSView(_ view: ClickControl, context: Context) {
            view.isEnabled = isEnabled
            view.isChecked = isChecked
            view.onToggle = onToggle
        }
    }

    final class ClickControl: NSView {
        var isEnabled = false
        var isChecked = false
        var onToggle: (() -> Void)?
        private var isPressed = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func isAccessibilityElement() -> Bool { isEnabled }
        override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
        override func accessibilityValue() -> Any? { isChecked ? 1 : 0 }

        override func accessibilityPerformPress() -> Bool {
            guard isEnabled, let onToggle else { return false }
            onToggle()
            return true
        }

        override func mouseDown(with event: NSEvent) {
            isPressed = isEnabled
        }

        override func mouseUp(with event: NSEvent) {
            defer { isPressed = false }
            guard isPressed, isEnabled,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            onToggle?()
        }
    }
}

extension Checkbox {
    
    func disabled(_ isDisabled: Bool) -> Self {
        var modified: Checkbox = self
        modified.disabled = isDisabled
        return modified
    }
    
    func onToggle(_ action: @escaping () -> Void) -> Self {
        var modified: Checkbox = self
        modified.onToggle = action
        return modified
    }
}
