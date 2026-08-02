//
//  NoteCompletionGauge.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import UIKit
import TildoneDomain

struct NoteCompletionGauge: View {
    let summary: NoteTaskSummary?

    private var completedCount: Int { summary?.completedCount ?? 0 }
    private var totalCount: Int { summary?.totalCount ?? 0 }
    private var completionFraction: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(completedCount) / CGFloat(totalCount)
    }
    private var tintColor: Color {
        let accentColor = UIColor(Color.accentColor)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard accentColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else {
            return Color(white: 0.82)
        }

        let minimumBrightness: CGFloat = 0.82
        return Color(
            hue: Double(hue),
            saturation: Double(saturation * completionFraction),
            brightness: Double(minimumBrightness + (brightness - minimumBrightness) * completionFraction),
            opacity: Double(alpha)
        )
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
        }
        .gaugeStyle(.accessoryCircular)
        .tint(tintColor)
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
