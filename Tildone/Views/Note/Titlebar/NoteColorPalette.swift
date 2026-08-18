//
//  NoteColorPalette.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct NoteColorPalette: View {
    let selected: NoteColor
    let onSelect: (NoteColor) -> Void

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NoteColor.allCases) { color in
                Button {
                    onSelect(color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle()
                                .stroke(
                                    selected == color ? Color.accentColor : .black.opacity(0.18),
                                    lineWidth: selected == color ? 3 : 0.75
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(color.localizedLabel)
                .accessibilityLabel(color.localizedLabel)
                .accessibilityAddTraits(selected == color ? .isSelected : [])
            }
        }
        .padding(10)
    }
}
