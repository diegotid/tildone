import CoreGraphics
import CoreText
import Foundation
import TildoneDomain

enum SingleMemoTypography {
    static let lineHeightMultiple: CGFloat = 0.9

    static var previewText: String {
        String(localized: "The quick brown fox jumps over the lazy dog")
    }

    static func fontName(for font: SingleMemoFont) -> String {
        switch font {
        case .overlock: "Overlock-Regular"
        case .pingFangSC: "PingFangSC-Regular"
        case .songtiSC: "STSongti-SC-Regular"
        case .notoSansSC: "NotoSansSC-Regular"
        case .notoSerifSC: "NotoSerifSC-Regular"
        case .coveredByYourGrace: "CoveredByYourGrace"
        case .craftyGirls: "CraftyGirls-Regular"
        case .lacquer: "Overlock-Regular"
        case .meowScript: "MeowScript-Regular"
        case .permanentMarker: "PermanentMarker-Regular"
        case .seaweedScript: "SeaweedScript-Regular"
        }
    }

    static func registerBundledFonts() {
        for font in SingleMemoFont.allCases {
            guard let fontURL = Bundle.main.url(
                forResource: resourceName(for: font),
                withExtension: "ttf"
            ) else { continue }
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    static func lineSpacing(for fontSize: CGFloat) -> CGFloat {
        fontSize * (lineHeightMultiple - 1)
    }

    private static func resourceName(for font: SingleMemoFont) -> String {
        switch font {
        case .overlock: "Overlock-Regular"
        case .pingFangSC: "PingFangSC-Regular"
        case .songtiSC: "STSongti-SC-Regular"
        case .notoSansSC: "NotoSansSC"
        case .notoSerifSC: "NotoSerifSC"
        case .coveredByYourGrace: "CoveredByYourGrace-Regular"
        case .craftyGirls: "CraftyGirls-Regular"
        case .lacquer: "Overlock-Regular"
        case .meowScript: "MeowScript-Regular"
        case .permanentMarker: "PermanentMarker-Regular"
        case .seaweedScript: "SeaweedScript-Regular"
        }
    }

    static let attributions: [FontAttribution] = [
        .init(
            font: .overlock,
            copyright: "Copyright © 2011 Dario Manuel Muhafara",
            license: "SIL Open Font License 1.1",
            sourceURL: "https://fonts.google.com/specimen/Overlock",
            licenseURL: "https://openfontlicense.org/"
        ),
        .init(
            font: .notoSansSC,
            copyright: "Copyright © 2014-2021 Adobe, with Reserved Font Name 'Source'",
            license: "SIL Open Font License 1.1",
            sourceURL: "https://fonts.google.com/specimen/Noto+Sans+SC",
            licenseURL: "https://openfontlicense.org/"
        ),
        .init(
            font: .notoSerifSC,
            copyright: "Copyright © 2017-2024 Adobe",
            license: "SIL Open Font License 1.1",
            sourceURL: "https://fonts.google.com/specimen/Noto+Serif+SC",
            licenseURL: "https://openfontlicense.org/"
        ),
        .init(
            font: .coveredByYourGrace,
            copyright: "Copyright © 2010 Kimberly Geswein",
            license: "SIL Open Font License 1.1",
            sourceURL: "https://fonts.google.com/specimen/Covered+By+Your+Grace",
            licenseURL: "https://openfontlicense.org/"
        ),
        .init(
            font: .craftyGirls,
            copyright: "Copyright © 2010 Font Diner, Inc DBA Tart Workshop",
            license: "Apache License 2.0",
            sourceURL: "https://fonts.google.com/specimen/Crafty+Girls",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0"
        ),
        .init(
            font: .meowScript,
            copyright: "Copyright © 2017 The Meow Script Project Authors",
            license: "SIL Open Font License 1.1",
            sourceURL: "https://fonts.google.com/specimen/Meow+Script",
            licenseURL: "https://openfontlicense.org/"
        ),
        .init(
            font: .permanentMarker,
            copyright: "Copyright © 2010 Font Diner, Inc",
            license: "Apache License 2.0",
            sourceURL: "https://fonts.google.com/specimen/Permanent+Marker",
            licenseURL: "https://www.apache.org/licenses/LICENSE-2.0"
        ),
        .init(
            font: .seaweedScript,
            copyright: "Copyright © 2012 Font Diner",
            license: "SIL Open Font License 1.1",
            sourceURL: "https://fonts.google.com/specimen/Seaweed+Script",
            licenseURL: "https://openfontlicense.org/"
        )
    ]

    struct FontAttribution: Identifiable {
        let font: SingleMemoFont
        let copyright: String
        let license: String
        let sourceURL: String
        let licenseURL: String

        var id: SingleMemoFont { font }
    }
}

extension SingleMemoFont {
    var isChinese: Bool {
        switch self {
        case .pingFangSC, .songtiSC, .notoSansSC, .notoSerifSC:
            true
        default:
            false
        }
    }

    var displayName: String {
        switch self {
        case .overlock: "Overlock"
        case .pingFangSC: "PingFang SC"
        case .songtiSC: "Songti SC"
        case .notoSansSC: "Noto Sans SC"
        case .notoSerifSC: "Noto Serif SC"
        case .coveredByYourGrace: "Covered By Your Grace"
        case .craftyGirls: "Crafty Girls"
        case .lacquer: "Overlock"
        case .meowScript: "Meow Script"
        case .permanentMarker: "Permanent Marker"
        case .seaweedScript: "Seaweed Script"
        }
    }
}
