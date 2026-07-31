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

    private var completedCount: Int { summary?.completedCount ?? 0 }
    private var totalCount: Int { summary?.totalCount ?? 0 }
    private var tintColor: Color {
        totalCount > 0 && completedCount == totalCount ? .green : .accentColor
    }

    var body: some View {
        Gauge(
            value: Double(completedCount),
            in: 0...Double(max(totalCount, 1))
        ) {
            EmptyView()
        } currentValueLabel: {
            Text("\(completedCount)/\(totalCount)")
                .font(.caption2.monospacedDigit().weight(.semibold))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.clear, tintColor]))
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
