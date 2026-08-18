//
//  NoteColorPickerIcon.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct NoteColorPickerIcon: View {
    let color: NoteColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
            Circle()
                .fill(Color(nsColor: color.nsColor))
                .padding(3)
                .overlay {
                    Circle()
                        .stroke(.black.opacity(0.15), lineWidth: 0.5)
                        .padding(3)
                }
        }
        .frame(width: 16, height: 16)
    }
}
