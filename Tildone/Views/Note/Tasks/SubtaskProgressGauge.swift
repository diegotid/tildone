//
//  SubtaskProgressGauge.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct SubtaskProgressGauge: View {
    let progress: TaskSubtaskProgress
    let size: CGFloat

    var body: some View {
        ZStack {
            if progress.fraction == 1 {
                Circle()
                    .fill(.accent)
                    .frame(width: size, height: size, alignment: .center)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.58, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color(.checkboxOffFill), lineWidth: max(2, size * 0.2))
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: max(2 * 0.7, size * 0.14), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(0.92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtask progress")
        .accessibilityValue("\(progress.completedCount) of \(progress.totalCount)")
    }
}
