//
//  SubtaskProgressGauge.swift
//  Tildone
//

import SwiftUI

struct SubtaskProgressGauge: View {
    let progress: TaskSubtaskProgress

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.checkboxBorder), lineWidth: 1)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress.completedCount == progress.totalCount {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: Layout.checkboxCheckSize, height: Layout.checkboxCheckSize)
            }
        }
        .frame(width: Layout.checkboxSize, height: Layout.checkboxSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtask progress")
        .accessibilityValue("\(progress.completedCount) of \(progress.totalCount)")
    }
}
