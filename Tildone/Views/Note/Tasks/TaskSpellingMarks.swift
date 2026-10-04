import AppKit
import SwiftUI

/// A drawing-only overlay; the SwiftUI text keeps its layout and hit testing.
struct TaskSpellingMarks: NSViewRepresentable {
    let text: AttributedString
    let ranges: [NSRange]

    func makeNSView(context: Context) -> TaskSpellingMarksView {
        TaskSpellingMarksView()
    }

    func updateNSView(_ view: TaskSpellingMarksView, context: Context) {
        view.update(text: NSAttributedString(text), ranges: ranges)
    }

    static func localRanges(_ ranges: [NSRange], offset: Int, length: Int) -> [NSRange] {
        let visibleRange = NSRange(location: offset, length: length)
        return ranges.compactMap { range in
            let intersection = NSIntersectionRange(range, visibleRange)
            guard intersection.length > 0 else { return nil }
            return NSRange(location: intersection.location - offset, length: intersection.length)
        }
    }
}
