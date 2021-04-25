//
//  Styler.swift
//  Tildone
//
//  Created by Diego on 25/4/21.
//

import SwiftUI

extension NSColor {
    
    static let noteBackground = #colorLiteral(red: 1, green: 0.9834647775, blue: 0.7855550647, alpha: 1)
    static let primaryFontColor = #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)
    static let checkboxBorder = #colorLiteral(red: 0.5011845827, green: 0.4942548871, blue: 0.4001311958, alpha: 0.5)
    static let checkboxOffFill = #colorLiteral(red: 0.9999960065, green: 1, blue: 1, alpha: 0.5)
    static let checkboxOnFill = #colorLiteral(red: 0, green: 0.5603182912, blue: 0, alpha: 1)
}

enum Layout {
    
    static let defaultNoteWidth: CGFloat = 250
    static let defaultNoteHeight: CGFloat = 300
    static let minNoteWidth: CGFloat = 100
    static let minNoteHeight: CGFloat = 120
    static let checkboxSize: CGFloat = 18
    static let checkboxCheckSize: CGFloat = 12
}
