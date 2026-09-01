import SwiftUI

struct TaskCheckboxIndicator: View {
    let isChecked: Bool
    let diameter: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let resolvedDiameter = pixelAligned(diameter)
        let lineWidth = pixelAligned(max(1, diameter / TaskControlMetrics.diameter))
        let checkDiameter = pixelAligned(diameter * 5 / 9)

        ZStack {
            Circle().fill(.white.opacity(0.5), style: FillStyle(antialiased: true))
            Circle().strokeBorder(
                isChecked ? Color.accentColor : checkboxBorder,
                lineWidth: lineWidth,
                antialiased: true
            )
            if isChecked {
                Circle().fill(Color.accentColor, style: FillStyle(antialiased: true))
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
