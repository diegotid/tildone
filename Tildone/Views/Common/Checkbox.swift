//
//  Checkbox.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI

struct Checkbox: View {
    var disabled: Bool = false
    @State var checked: Bool = false
    
    var body: some View {
        return ZStack {
            Circle()
                .fill(Color(.checkboxOffFill))
                .overlay(Circle().stroke(Color(self.checked ? .checkboxOnFill : .checkboxBorder)))
                .frame(width: Layout.checkboxSize, height: Layout.checkboxSize, alignment: .center)
                .opacity(disabled ? 0.6 : 1)
                .onTapGesture(count: 1) {
                    if !disabled {
                        self.checked.toggle()
                    }
                }
            if self.checked {
                Circle()
                    .fill(Color(.checkboxOnFill))
                    .frame(width: Layout.checkboxCheckSize,
                           height: Layout.checkboxCheckSize,
                           alignment: .center)
                    .onTapGesture(count: 1, perform: {
                        self.checked.toggle()
                    })
            }
        }
    }
}
