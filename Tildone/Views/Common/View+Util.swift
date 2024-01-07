//
//  View+Util.swift
//  Tildone
//
//  Created by Diego Rivera on 7/1/24.
//

import SwiftUI

extension View {
    @ViewBuilder func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
