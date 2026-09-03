import AppKit
import SwiftUI

struct FirstLineTruncatingWrappedTaskText: View {
    let text: String
    let fontSize: CGFloat
    let color: Color
    let reservedTrailingWidth: CGFloat
    @State private var availableWidth: CGFloat = 0

    private var lineSegments: (first: String, remaining: String)? {
        guard availableWidth > reservedTrailingWidth else { return nil }

        let font = NSFont.systemFont(ofSize: fontSize)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: availableWidth, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        layoutManager.replaceTextStorage(storage)

        let glyphRange = layoutManager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return (text, "") }

        var firstLineGlyphRange = NSRange()
        layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: &firstLineGlyphRange
        )
        let firstLineCharacterRange = layoutManager.characterRange(
            forGlyphRange: firstLineGlyphRange,
            actualGlyphRange: nil
        )
        guard let firstLineRange = Range(firstLineCharacterRange, in: text) else {
            return nil
        }

        let first = String(text[firstLineRange])
        var remainingStart = firstLineRange.upperBound
        if remainingStart < text.endIndex, text[remainingStart] == "\n" {
            remainingStart = text.index(after: remainingStart)
        }
        return (first, String(text[remainingStart...]))
    }

    var body: some View {
        Group {
            if let lineSegments {
                VStack(alignment: .leading, spacing: 0) {
                    Text(lineSegments.first)
                        .font(.system(size: fontSize))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(
                            width: availableWidth - reservedTrailingWidth,
                            alignment: .leading
                        )
                    if !lineSegments.remaining.isEmpty {
                        Text(lineSegments.remaining)
                            .font(.system(size: fontSize))
                            .foregroundStyle(color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text(text)
                    .font(.system(size: fontSize))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        availableWidth = width
                    }
            }
        }
    }
}
