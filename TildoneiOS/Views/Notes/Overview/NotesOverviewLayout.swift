import SwiftUI

enum NotesOverviewLayout: String, CaseIterable, Identifiable {
    case list
    case grid
    case deck

    var id: Self { self }

    var title: String {
        switch self {
        case .list: String(localized: "List")
        case .grid: String(localized: "Grid")
        case .deck: String(localized: "Deck")
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .deck: "rectangle.stack"
        }
    }
}
