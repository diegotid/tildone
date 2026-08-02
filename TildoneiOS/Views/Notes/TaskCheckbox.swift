//
//  TaskCheckbox.swift
//  Tildone
//
//  Created by Diego Rivera on 8/2/26.
//
import SwiftUI

struct TaskCheckbox: View {
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.5))
                    .overlay {
                        Circle()
                            .stroke(isChecked ? Color.accentColor : checkboxBorder, lineWidth: 1)
                    }
                    .frame(width: 18, height: 18)

                if isChecked {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 32, height: 33)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isChecked ? "Mark task incomplete" : "Complete task")
    }

    private var checkboxBorder: Color {
        Color(red: 0.534, green: 0.507, blue: 0.339)
    }
}
