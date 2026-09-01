//
//  TaskCheckbox.swift
//  Tildone
//
//  Created by Diego Rivera on 8/2/26.
//
import SwiftUI
import TildoneDomain

enum TaskControlMetrics {
    static let diameter: CGFloat = 16
}

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

struct TaskCheckboxIndicator: View {
    let isChecked: Bool
    let diameter: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let resolvedDiameter = pixelAligned(diameter)
        let lineWidth = pixelAligned(max(1, diameter / TaskControlMetrics.diameter))
        let checkDiameter = pixelAligned(diameter * 5 / 9)

        ZStack {
            Circle()
                .fill(.white.opacity(0.5), style: FillStyle(antialiased: true))

            Circle()
                .strokeBorder(
                    isChecked ? Color.accentColor : checkboxBorder,
                    lineWidth: lineWidth,
                    antialiased: true
                )

            if isChecked {
                Circle()
                    .fill(Color.accentColor, style: FillStyle(antialiased: true))
                    .frame(width: checkDiameter, height: checkDiameter)
            }
        }
        .frame(width: resolvedDiameter, height: resolvedDiameter)
        .accessibilityHidden(true)
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        (value * displayScale).rounded(.toNearestOrAwayFromZero) / displayScale
    }

    private var checkboxBorder: Color {
        Color(red: 0.534, green: 0.507, blue: 0.339)
    }
}

struct TaskSubtaskProgressGauge: View {
    let progress: TaskSubtaskProgress
    let size: CGFloat

    init(progress: TaskSubtaskProgress, size: CGFloat = TaskControlMetrics.diameter) {
        self.progress = progress
        self.size = size
    }

    var body: some View {
        ZStack {
            if progress.fraction == 1 {
                Circle()
                    .fill(.accent)
                    .frame(width: size, height: size)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.58, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(checkboxBorder, lineWidth: max(2, size * 0.2))
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: max(2, size * 0.14), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtask progress")
        .accessibilityValue("\(progress.completedCount) of \(progress.totalCount)")
    }

    private var checkboxBorder: Color {
        .gray.opacity(0.35)
    }
}
