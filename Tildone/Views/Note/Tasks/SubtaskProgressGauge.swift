//
//  SubtaskProgressGauge.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct SubtaskProgressGauge: View {
    let progress: TaskSubtaskProgress

    var body: some View {
        ZStack {
            if progress.fraction < 1 {
                Circle()
                    .fill(Color(.checkboxOffFill))
                    .frame(width: Layout.checkboxSize, height: Layout.checkboxSize, alignment: .center)
                Circle()
                    .stroke(Color(.checkboxBorder))
            }
            PizzaSlice(startAngle: .degrees(0), endAngle: .degrees(progress.fraction * 360))
                .fill(Color.accentColor)
                .frame(width: Layout.checkboxSize, height: Layout.checkboxSize, alignment: .center)
                .rotationEffect(.degrees(-90))
            if progress.fraction == 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
                    .bold()
            }
        }
        .frame(width: Layout.checkboxSize, height: Layout.checkboxSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtask progress")
        .accessibilityValue("\(progress.completedCount) of \(progress.totalCount)")
    }
}
