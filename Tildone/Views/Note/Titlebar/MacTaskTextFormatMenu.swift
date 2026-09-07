//
//  MacTaskTextFormatMenu.swift
//  Tildone
//
import AppKit
import SwiftUI
import TildoneDomain

struct MacTaskTextFormatMenu: View {
    let foreground: Color

    init(foreground: Color = .primary) {
        self.foreground = foreground
    }

    var body: some View {
        Menu {
            formatButton("Bold", systemImage: "bold", format: .toggle(.bold))
            formatButton("Italic", systemImage: "italic", format: .toggle(.italic))
            formatButton("Underline", systemImage: "underline", format: .toggle(.underline))
            formatButton("Strikethrough", systemImage: "strikethrough", format: .toggle(.strikethrough))
            Divider()
            colorMenu("Text color", systemImage: "textformat", isHighlight: false)
            colorMenu("Highlight", systemImage: "highlighter", isHighlight: true)
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foreground)
                .frame(width: MacNoteTitlebarLayout.formatControlWidth, height: MacNoteTitlebarLayout.controlHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(foreground)
        .help("Format task text")
        .accessibilityLabel("Format task text")
    }

    private func formatButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        format: RichTextFormat
    ) -> some View {
        Button {
            NotificationCenter.default.post(name: .formatTaskText, object: format)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .tint(.primary)
    }

    private func colorMenu(
        _ title: LocalizedStringKey,
        systemImage: String,
        isHighlight: Bool
    ) -> some View {
        Menu {
            Button("Default") { postColor(nil, isHighlight: isHighlight) }
            Divider()
            ForEach(RichTextColor.allCases) { color in
                Button {
                    postColor(color, isHighlight: isHighlight)
                } label: {
                    Label {
                        Text(color.localizedLabel)
                    } icon: {
                        Image(nsImage: color.menuPreviewImage(isHighlight: isHighlight))
                            .renderingMode(.original)
                    }
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .tint(.primary)
    }

    private func postColor(_ color: RichTextColor?, isHighlight: Bool) {
        NotificationCenter.default.post(
            name: .formatTaskText,
            object: isHighlight ? RichTextFormat.highlight(color) : .foreground(color)
        )
    }
}

private extension RichTextColor {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .gray: "Gray"
        }
    }

    func menuPreviewImage(isHighlight: Bool) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { bounds in
            let swatchBounds = bounds.insetBy(dx: 1, dy: 1)
            let path = isHighlight
                ? NSBezierPath(roundedRect: swatchBounds, xRadius: 3, yRadius: 3)
                : NSBezierPath(ovalIn: swatchBounds)

            if isHighlight {
                menuColor.withAlphaComponent(0.34).setFill()
                path.fill()
                menuColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            } else {
                menuColor.setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    var menuColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }
}
