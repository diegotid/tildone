import SwiftUI

enum NoteCardLayoutMetrics {
    private static let deckSizeMultiplier: CGFloat = 0.86

    static func gridHeight(in availableHeight: CGFloat) -> CGFloat {
        min(260, max(170, (availableHeight - 36) / 2.35))
    }

    static func deckHeight(in availableHeight: CGFloat) -> CGFloat {
        min(availableHeight * 0.60, 420) * deckSizeMultiplier
    }

    static func deckWidth(in availableWidth: CGFloat) -> CGFloat {
        min(availableWidth * 0.72, 320) * deckSizeMultiplier
    }
}
