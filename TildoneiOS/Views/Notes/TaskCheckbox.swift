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
            TaskCheckboxIndicator(isChecked: isChecked, diameter: 18)
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
        let lineWidth = pixelAligned(max(1, diameter / 18))
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

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.5))
            Circle()
                .strokeBorder(Color(red: 0.534, green: 0.507, blue: 0.339), lineWidth: 1)
            if progress.fraction > 0 {
                TaskProgressSlice(fraction: progress.fraction)
                    .fill(Color.accentColor)
            }
            if progress.fraction == 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtask progress")
        .accessibilityValue("\(progress.completedCount) of \(progress.totalCount)")
    }
}

private struct TaskProgressSlice: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + min(max(fraction, 0), 1) * 360),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
