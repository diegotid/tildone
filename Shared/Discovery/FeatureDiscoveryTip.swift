import SwiftUI
import TipKit

struct FeatureDiscoveryTip: Tip {
    enum Kind: String { case subtasks, dimming, gathering }
    let kind: Kind
    var contentColor: Color? = nil
    var id: String { "discovery-\(kind.rawValue)" }

    var title: Text {
        titleText.foregroundColor(contentColor)
    }

    private var titleText: Text {
        switch kind {
        case .subtasks: Text("Keep smaller steps together")
        case .dimming: Text("Dim one note or all of them")
        case .gathering: Text("Gather, then return")
        }
    }

    var message: Text? {
        messageText.foregroundColor(contentColor)
    }

    private var messageText: Text {
        switch kind {
        case .subtasks:
            #if os(macOS)
            Text("Use this menu to make a subtask or promote it. Creating or changing hierarchy requires Pro.")
            #else
            Text("Swipe a task to make a subtask or promote it. Creating or changing hierarchy requires Pro.")
            #endif
        case .dimming:
            Text("Hold your dimming shortcut and scroll over a note. Add Shift to change all notes together.")
        case .gathering:
            Text("Hold your gathering shortcut and scroll down over a note. Scroll up to restore the notes to their previous positions.")
        }
    }

    var options: [TipOption] { [Tips.MaxDisplayCount(1)] }

    static func configure() {
        guard !WhatsNewRelease.isIsolatedProcess else { return }
        try? Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])
    }
}
