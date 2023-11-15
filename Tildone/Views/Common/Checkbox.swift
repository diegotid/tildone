//
//  Checkbox.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI

struct Checkbox: View {
    @State var checked: Bool = false

    var disabled: Bool = false
    var onToggle: (() -> Void)?

    var body: some View {
        return ZStack {
            Circle()
                .fill(Color(.checkboxOffFill))
                .overlay(Circle().stroke(Color(self.checked ? .checkboxOnFill : .checkboxBorder)))
                .frame(width: Layout.checkboxSize, height: Layout.checkboxSize, alignment: .center)
                .opacity(disabled ? 0.6 : 1)
                .onTapGesture(count: 1) {
                    if !disabled, let toggle = onToggle {
                        toggle()
                        self.checked.toggle()
                    }
                }
            if self.checked {
                Circle()
                    .fill(Color(.checkboxOnFill))
                    .frame(width: Layout.checkboxCheckSize,
                           height: Layout.checkboxCheckSize,
                           alignment: .center)
                    .onTapGesture(count: 1) {
                        if let toggle = onToggle {
                            toggle()
                            self.checked.toggle()
                        }
                    }
            }
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
