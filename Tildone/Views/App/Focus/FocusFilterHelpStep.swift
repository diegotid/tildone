//
//  FocusFilterHelpStep.swift
//  Tildone
//

import SwiftUI

struct FocusFilterHelpStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}
