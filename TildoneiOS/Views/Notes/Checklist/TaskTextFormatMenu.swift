//
//  TaskTextFormatMenu.swift
//  Tildone
//
import SwiftUI
import TildoneDomain
import UIKit

struct TaskTextFormatMenu: View {
    let isEnabled: Bool
    var selectedFont: SingleMemoFont? = nil
    var onFontChange: ((SingleMemoFont) -> Void)? = nil

    var body: some View {
        Menu {
            button("Bold", systemImage: "bold", format: .toggle(.bold))
            button("Italic", systemImage: "italic", format: .toggle(.italic))
            button("Underline", systemImage: "underline", format: .toggle(.underline))
            button("Strikethrough", systemImage: "strikethrough", format: .toggle(.strikethrough))
            Divider()
            colorMenu("Text color", systemImage: "textformat", isHighlight: false)
            colorMenu("Highlight", systemImage: "highlighter", isHighlight: true)
            if let selectedFont, let onFontChange {
                Divider()
                Menu {
                    ForEach(SingleMemoFont.allCases) { font in
                        Button {
                            onFontChange(font)
                        } label: {
                            if selectedFont == font {
                                Label(font.displayName, systemImage: "checkmark")
                                    .font(.custom(SingleMemoTypography.fontName(for: font), size: 17))
                            } else {
                                Text(verbatim: font.displayName)
                                    .font(.custom(SingleMemoTypography.fontName(for: font), size: 17))
                            }
                        }
                    }
                } label: {
                    Label("Font", systemImage: "textformat.size")
                }
            }
        } label: {
            Image(systemName: "textformat")
        }
        // Keep the control visually enabled. UIKit can briefly lag the
        // FocusState update while installing the selection; the editor itself
        // remains the authority for whether a command has a target.
        .foregroundStyle(.primary)
        .accessibilityLabel("Format task text")
    }

    private func button(
        _ title: LocalizedStringKey,
        systemImage: String,
        format: RichTextFormat
    ) -> some View {
        Button {
            NotificationCenter.default.post(name: .formatTaskText, object: format)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func colorMenu(
        _ title: LocalizedStringKey,
        systemImage: String,
        isHighlight: Bool
    ) -> some View {
        Menu {
            Button("Default") { post(nil, isHighlight: isHighlight) }
            Divider()
            ForEach(RichTextColor.allCases) { color in
                Button {
                    post(color, isHighlight: isHighlight)
                } label: {
                    Label {
                        Text(color.localizedLabel)
                    } icon: {
                        Image(uiImage: color.menuPreviewImage(isHighlight: isHighlight))
                            .renderingMode(.original)
                    }
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func post(_ color: RichTextColor?, isHighlight: Bool) {
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

    func menuPreviewImage(isHighlight: Bool) -> UIImage {
        let size = CGSize(width: 18, height: 18)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let swatchBounds = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let path = isHighlight
                ? UIBezierPath(roundedRect: swatchBounds, cornerRadius: 4)
                : UIBezierPath(ovalIn: swatchBounds)

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
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    var menuColor: UIColor {
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
