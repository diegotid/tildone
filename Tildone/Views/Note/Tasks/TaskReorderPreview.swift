//
//  TaskReorderPreview.swift
//  Tildone
//

import SwiftUI

struct TaskReorderPreview: View {
    let taskText: String
    let isCompleted: Bool
    let fontSize: Double
    let isDark: Bool

    var body: some View {
        HStack(spacing: 8) {
            Checkbox(checked: isCompleted)
                .disabled(true)

            Text(taskText.isEmpty ? String(localized: "Untitled task") : taskText)
                .font(.system(size: CGFloat(fontSize)))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(
                    (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor))
                        .opacity(isCompleted ? 0.6 : 1)
                )
                .overlay {
                    if isCompleted {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .offset(y: 1)
                    }
                }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).opacity(0.45)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, isDark ? .dark : .light)
    }
}
