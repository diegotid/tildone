import CoreGraphics
import CoreText
import Foundation

enum SingleMemoTypography {
    static let fontName = "Overlock-Regular"
    static let lineHeightMultiple: CGFloat = 0.8

    static func registerBundledFont() {
        guard let fontURL = Bundle.main.url(forResource: "Overlock-Regular", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }

    static func lineSpacing(for fontSize: CGFloat) -> CGFloat {
        fontSize * (lineHeightMultiple - 1)
    }
}
