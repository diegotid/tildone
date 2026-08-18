//
//  ScrollFrame.swift
//  Tildone
//

import SwiftUI

struct ScrollFrame: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.top, 0).padding(.trailing, 5).padding(.leading, 20).colorScheme(.light)
    }
}
