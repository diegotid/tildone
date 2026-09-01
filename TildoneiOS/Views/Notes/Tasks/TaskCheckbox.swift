//
//  TaskCheckbox.swift
//  Tildone
//
//  Created by Diego Rivera on 8/2/26.
//
import SwiftUI
import TildoneDomain

struct TaskCheckbox: View {
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            TaskCheckboxIndicator(isChecked: isChecked, diameter: TaskControlMetrics.diameter)
                .frame(width: 32, height: 33)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isChecked ? "Mark task incomplete" : "Complete task")
    }
}
