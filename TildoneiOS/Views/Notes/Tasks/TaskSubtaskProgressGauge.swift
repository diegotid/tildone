import SwiftUI
import TildoneDomain

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
                Circle().fill(.accent).frame(width: size * 1.1, height: size * 1.1)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.6, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().stroke(checkboxBorder, lineWidth: max(2, size * 0.2))
                Circle().trim(from: 0, to: progress.fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: max(2, size * 0.14), lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtask progress")
        .accessibilityValue("\(progress.completedCount) of \(progress.totalCount)")
    }

    private var checkboxBorder: Color { .gray.opacity(0.35) }
}
