//
//  NoteCompletionGauge.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneDomain

struct NoteCompletionGauge: View {
    let summary: NoteTaskSummary?
    var labelColor: Color = .primary

    private var completedCount: Int { summary?.completedCount ?? 0 }
    private var totalCount: Int { summary?.totalCount ?? 0 }
    private var completionFraction: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(completedCount) / CGFloat(totalCount)
    }
    private var tintColor: Color {
        Color.accentColor.opacity(0.22 + Double(completionFraction) * 0.78)
    }

    var body: some View {
        Gauge(
            value: Double(completedCount),
            in: 0...Double(max(totalCount, 1))
        ) {
            EmptyView()
        } currentValueLabel: {
            Text("\(completedCount)/\(totalCount)")
                .font(.callout.monospacedDigit().weight(.light))
                .foregroundStyle(labelColor)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(tintColor)
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
