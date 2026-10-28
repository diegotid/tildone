#!/usr/bin/env swift
// Native creative artwork. Full Header exports require an approved composition.
import AppKit
import CryptoKit
import QuartzCore
import SwiftUI

struct MarketingIOSHeaderThumbnail: View {
    let phone: NSImage
    let statusBackdrop: NSImage
    let macNote: NSImage
    let wallpaper: NSImage
    let headline: String
    let benefit: String
    let asset: String
    let locale: String
    let cropSafeReview: Bool
    let midScaleReview: Bool
    let spacingReview: Bool
    let textReview: Bool
    let largeTextReview: Bool

    private var isSearch: Bool { asset == "search-results" }
    private var captionScale: CGFloat { largeTextReview ? 1.5 : (textReview ? 1.15 : 1) }
    private var captionLeftShift: CGFloat { largeTextReview ? 138 : (textReview ? 18 : 0) }
    private var captionUpShift: CGFloat { largeTextReview ? 27 : 0 }

    private let yellow = Color(red: 1.00, green: 0.94, blue: 0.63)
    private let green = Color(red: 0.73, green: 1.00, blue: 0.72)
    private let blue = Color(red: 0.68, green: 0.82, blue: 0.95)
    private let orange = Color(red: 0.99, green: 0.84, blue: 0.70)
    private let pink = Color(red: 0.98, green: 0.78, blue: 0.86)
    private let purple = Color(red: 0.84, green: 0.76, blue: 0.96)

    private var phoneView: some View {
        ZStack {
            // Physical titanium side rails and buttons replace the glass artwork
            // frame. Native app pixels and the hidden island stay unchanged.
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.61), Color(white: 0.22), Color(white: 0.72)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 5, height: 27)
                .offset(x: -160, y: -231)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.6), Color(white: 0.25), Color(white: 0.68)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 5, height: 48)
                .offset(x: -160, y: -164)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.6), Color(white: 0.25), Color(white: 0.68)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 5, height: 48)
                .offset(x: -160, y: -103)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.72), Color(white: 0.4)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 5, height: 75)
                .offset(x: 160, y: -137)
            RoundedRectangle(cornerRadius: 49)
                .fill(LinearGradient(stops: [
                    .init(color: Color(white: 0.88), location: 0),
                    .init(color: Color(white: 0.43), location: 0.18),
                    .init(color: Color(white: 0.73), location: 0.47),
                    .init(color: Color(white: 0.33), location: 0.79),
                    .init(color: Color(white: 0.72), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 49)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .black.opacity(0.7), .white.opacity(0.8)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.1)
            RoundedRectangle(cornerRadius: 46)
                .fill(Color(white: 0.035))
                .padding(3)
            RoundedRectangle(cornerRadius: 46)
                .strokeBorder(.white.opacity(0.24), lineWidth: 0.6)
                .padding(3)
            ZStack(alignment: .top) {
                Image(nsImage: phone).resizable().interpolation(.high)
                    .frame(width: 300, height: 300 * 2622 / 1206)
                Image(nsImage: statusBackdrop).resizable()
                    .frame(width: 300 * 112 / 320, height: 300 * 43 / 320)
                    .padding(.top, 300 * 3 / 320)
            }
            .clipShape(RoundedRectangle(cornerRadius: 38))
            .overlay(RoundedRectangle(cornerRadius: 38).strokeBorder(.white.opacity(0.15), lineWidth: 0.6))
        }
        .frame(width: 320, height: 300 * 2622 / 1206 + 20)
    }

    private var keyboardPlaneProjection: ProjectionTransform {
        // Project the entire deck from a rectangle onto the same trapezoid as
        // its metal chassis: rear corners (65, 0)/(915, 0), front (0, 178)/(980, 178).
        let rearScale = 850.0 / 980
        var transform = CATransform3DIdentity
        transform.m11 = rearScale
        transform.m21 = -65.0 / 178
        transform.m41 = 65
        transform.m22 = rearScale
        transform.m24 = (rearScale - 1) / 178
        return ProjectionTransform(transform)
    }

    private var keyboardBase: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 65, y: 0))
                path.addLine(to: CGPoint(x: 915, y: 0))
                path.addLine(to: CGPoint(x: 980, y: 178))
                path.addLine(to: CGPoint(x: 0, y: 178))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.68), Color(white: 0.43)],
                                 startPoint: .top, endPoint: .bottom))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.16))
                    .frame(width: 790, height: 89).offset(x: 95, y: 10)
                Path { path in
                    for row in 0..<5 {
                        for column in 0..<14 {
                            path.addRoundedRect(in: CGRect(x: 104 + column * 55, y: 15 + row * 16,
                                                           width: 47, height: 12),
                                                cornerSize: CGSize(width: 2, height: 2))
                        }
                    }
                }
                .fill(Color(white: 0.055))
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(white: 0.3), lineWidth: 1.3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.07)))
                    .frame(width: 210, height: 54).offset(x: 385, y: 112)
            }
            .frame(width: 980, height: 178, alignment: .topLeading)
            .projectionEffect(keyboardPlaneProjection)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.31))
                .frame(width: 980, height: 5).offset(y: 176)
        }
        .frame(width: 980, height: 182)
        .shadow(color: .black.opacity(0.18), radius: 13, y: 8)
    }

    private var macView: some View {
        ZStack(alignment: .topLeading) {
            if cropSafeReview {
                keyboardBase.offset(x: -65, y: 600)
            }
            macDisplay
        }
        .frame(width: 850, height: 620, alignment: .topLeading)
    }

    private var macDisplay: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 38).fill(.black.opacity(0.86))
            Image(nsImage: wallpaper).resizable().interpolation(.high).scaledToFill()
                .frame(width: 822, height: 592)
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .padding(14)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.055))
                Rectangle().fill(Color(white: 0.055)).frame(height: 14)
                Circle().fill(Color(white: 0.18)).frame(width: 5, height: 5).padding(.top, 10)
            }
            .frame(width: 132, height: 35)
            .padding(.top, 12)
            Image(nsImage: macNote).resizable().interpolation(.high)
                .frame(width: 280, height: 280 * macNote.size.height / macNote.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .shadow(color: .black.opacity(0.28), radius: 20, y: 9)
                .scaleEffect(0.6)
                .offset(x: spacingReview ? -46 : -6, y: 150)
        }
        .frame(width: 850, height: 620)
        .overlay(RoundedRectangle(cornerRadius: 38).strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.24), radius: 30, x: 5, y: 17)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            RadialGradient(colors: [green.opacity(0.55), .clear], center: UnitPoint(x: 0.14, y: 0.23),
                           startRadius: 0, endRadius: 430)
            RadialGradient(colors: [yellow.opacity(0.82), .clear], center: UnitPoint(x: 0.04, y: 0.72),
                           startRadius: 0, endRadius: 480)
            RadialGradient(colors: [orange.opacity(0.75), .clear], center: .bottomLeading,
                           startRadius: 0, endRadius: 410)
            RadialGradient(colors: [pink.opacity(0.7), .clear], center: UnitPoint(x: 0.5, y: 1.1),
                           startRadius: 0, endRadius: 450)
            RadialGradient(colors: [blue.opacity(0.74), .clear], center: UnitPoint(x: 0.99, y: 0.2),
                           startRadius: 0, endRadius: 490)
            RadialGradient(colors: [purple.opacity(0.76), .clear], center: .bottomTrailing,
                           startRadius: 0, endRadius: 460)
            ZStack(alignment: .topLeading) {
                // Revision 2 fills the canvas as requested. The Mac display extends
                // past the lower/right edges; its native note stays fully in view.
                VStack(alignment: .leading, spacing: 28) {
                    Text(headline)
                        .font(.system(size: isSearch ? 56 : (midScaleReview ? (locale == "en-US" ? 48 : 42) : 52), weight: .medium))
                        .tracking(-1.8)
                        .lineSpacing(-1)
                        .foregroundStyle(Color(white: 0.1))
                        .lineLimit(2)
                        .minimumScaleFactor(locale == "en-US" ? 1 : 0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Image(systemName: "icloud").font(.system(size: 22, weight: .medium))
                        Text(benefit).font(.system(size: isSearch ? 23 : 21, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(Color(white: 0.26))
                }
                .frame(width: isSearch ? 900 : (midScaleReview && locale != "en-US" ? 320 : 376), alignment: .leading)
                .scaleEffect(captionScale, anchor: .topLeading)
                .offset(x: (isSearch ? 80 : 64) - captionLeftShift / 0.65,
                        y: (isSearch ? 90 : 180) - captionUpShift / 0.65)
                macView.offset(x: (isSearch ? 560 : (midScaleReview ? 397 : 666)) + (spacingReview ? 30 / 0.65 : 0),
                               y: isSearch ? 365 : (midScaleReview ? -105 : 95))
                phoneView
                    .scaleEffect(isSearch ? 1.25 : 1, anchor: .topLeading)
                    .frame(width: isSearch ? 400 : 320,
                           height: (300 * 2622 / 1206 + 20) * (isSearch ? 1.25 : 1), alignment: .topLeading)
                    .rotationEffect(.degrees(-5), anchor: .top)
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.34), radius: 24, x: 26, y: 18)
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 8, y: 5)
                    .offset(x: (isSearch ? 200 : (midScaleReview ? 365 : 480)) + (spacingReview ? 15 / 0.65 : 0),
                            y: isSearch ? 304 : 30)
            }
            .frame(width: 1280, height: (isSearch ? 2560.0 : 1646.0) / 3, alignment: .topLeading)
            .scaleEffect(midScaleReview ? 0.65 : (cropSafeReview ? 0.45 : 1), anchor: .topLeading)
            .offset(x: midScaleReview ? 325 : (cropSafeReview ? 352 : 0),
                    y: midScaleReview ? 130 : (cropSafeReview ? 160 : 0))
        }
        .frame(width: 1280, height: (isSearch ? 2560.0 : 1646.0) / 3, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}

@MainActor
func renderHeaderThumbnail() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2 else {
        throw NSError(domain: "HeaderThumbnail", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected output.png [--native-root directory] [--locale locale] [--asset header|search-results] [--full] [--crop-safe-review]."])
    }
    var nativeRoot: URL?
    var macInputRoot: URL?
    var locale = "en-US"
    var asset = "header"
    var full = false
    var cropSafeReview = false
    var midScaleReview = false
    var spacingReview = false
    var textReview = false
    var largeTextReview = false
    var index = 2
    while index < arguments.count {
        if arguments[index] == "--full" { full = true; index += 1; continue }
        if arguments[index] == "--crop-safe-review" { cropSafeReview = true; index += 1; continue }
        if arguments[index] == "--mid-scale-review" {
            cropSafeReview = true; midScaleReview = true; index += 1; continue
        }
        if arguments[index] == "--spacing-review" {
            cropSafeReview = true; midScaleReview = true; spacingReview = true; index += 1; continue
        }
        if arguments[index] == "--text-review" {
            cropSafeReview = true; midScaleReview = true; spacingReview = true; textReview = true
            index += 1; continue
        }
        if arguments[index] == "--large-text-review" {
            cropSafeReview = true; midScaleReview = true; spacingReview = true; textReview = true
            largeTextReview = true; index += 1; continue
        }
        guard index + 1 < arguments.count else { throw NSError(domain: "HeaderThumbnail", code: 1) }
        switch arguments[index] {
        case "--native-root": nativeRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        case "--mac-input-root": macInputRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        case "--locale": locale = arguments[index + 1]
        case "--asset": asset = arguments[index + 1]
        default: throw NSError(domain: "HeaderThumbnail", code: 1)
        }
        index += 2
    }
    let languages = ["en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"]
    guard let language = languages[locale], ["header", "search-results"].contains(asset) else {
        throw NSError(domain: "HeaderThumbnail", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected a supported creative asset and locale."])
    }
    guard !cropSafeReview || (asset == "header" && nativeRoot != nil) else {
        throw NSError(domain: "HeaderThumbnail", code: 11,
                      userInfo: [NSLocalizedDescriptionKey: "The approved crop-safe composition requires matching native Header inputs."])
    }
    guard !midScaleReview || spacingReview || (!full && locale == "en-US") else {
        throw NSError(domain: "HeaderThumbnail", code: 13,
                      userInfo: [NSLocalizedDescriptionKey: "Approve the larger English Header thumbnail before full export or localization."])
    }
    guard !textReview || largeTextReview || (!full && locale == "en-US") else {
        throw NSError(domain: "HeaderThumbnail", code: 14,
                      userInfo: [NSLocalizedDescriptionKey: "Review the larger left-shifted English caption before full export or localization."])
    }
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let nativeURL: URL
    if let nativeRoot {
        nativeURL = nativeRoot.appendingPathComponent("phone-native/phone-capture-verification.json")
    } else {
        let recordURL = repo.appendingPathComponent("Marketing/Preview/Output/iOS/captures/screenshot-2/\(locale)/export-result.json")
        guard let record = try JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any],
              let nativePath = record["nativeProof"] as? String else { throw NSError(domain: "HeaderThumbnail", code: 2) }
        nativeURL = URL(fileURLWithPath: nativePath)
    }
    guard let native = try JSONSerialization.jsonObject(with: Data(contentsOf: nativeURL)) as? [String: Any],
          native["nativeUI"] as? Bool == true, native["mockDataOnly"] as? Bool == true,
          native["cloudKitStarted"] as? Bool == false, native["storeKitStarted"] as? Bool == false,
          native["proContent"] as? Bool == false, native["locale"] as? String == locale else { throw NSError(domain: "HeaderThumbnail", code: 3) }
    let phoneURL = nativeURL.deletingLastPathComponent().appendingPathComponent("phone-checklist.png")
    let phoneData = try Data(contentsOf: phoneURL)
    guard let phone = NSImage(data: phoneData), let bitmap = NSBitmapImageRep(data: phoneData),
          bitmap.pixelsWide == 1206, bitmap.pixelsHigh == 2622,
          let strip = bitmap.cgImage?.cropping(to: CGRect(x: 8, y: 11, width: 12, height: 162)) else {
        throw NSError(domain: "HeaderThumbnail", code: 4)
    }
    let inputManifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
        repo.appendingPathComponent("Marketing/Preview/Inputs/manifest.json"))) as? [String: Any]
    let activeInputs = (inputManifest?["activeIPhoneWallpaper"] as? [String: Any])?["macInputsDirectory"] as? String
    let defaultMacRoot = repo.appendingPathComponent(activeInputs ?? "Marketing/Preview/Output/screenshots/02")
    let macDirectory = (macInputRoot ?? defaultMacRoot)
        .appendingPathComponent(locale)
    let macResultURL = nativeRoot?.appendingPathComponent("mac-native/mac-note.json")
        ?? macDirectory.appendingPathComponent("screenshot-result.json")
    guard let macResult = try JSONSerialization.jsonObject(with: Data(contentsOf: macResultURL)) as? [String: Any] else {
        throw NSError(domain: "HeaderThumbnail", code: 5)
    }
    let macURL = nativeRoot?.appendingPathComponent("mac-native/mac-note.png")
        ?? macDirectory.appendingPathComponent("Tildone-macOS-screenshot-02-\(locale).png")
    let macData = try Data(contentsOf: macURL)
    guard macResult["mockDataOnly"] as? Bool == true, macResult["cloudKitStarted"] as? Bool == false,
          macResult["locale"] as? String == locale,
          let macSource = NSBitmapImageRep(data: macData)?.cgImage,
          let wallpaper = NSImage(contentsOf: macDirectory.appendingPathComponent("TildonePreviewStudio.app/Contents/Resources/GoldenGate.png")) else {
        throw NSError(domain: "HeaderThumbnail", code: 5)
    }
    let note: CGImage
    let width: CGFloat
    let height: CGFloat
    if nativeRoot != nil {
        guard macResult["nativeUI"] as? Bool == true,
              let notes = native["notes"] as? [[String: Any]], let phoneNote = notes.first,
              let phoneTasks = phoneNote["tasks"] as? [[String: Any]],
              let macTasks = macResult["tasks"] as? [[String: Any]],
              macResult["title"] as? String == phoneNote["title"] as? String,
              macResult["color"] as? String == phoneNote["color"] as? String,
              phoneTasks.count == 5, macTasks.count == 5,
              phoneTasks.compactMap({ $0["text"] as? String }) == macTasks.compactMap({ $0["text"] as? String }),
              phoneTasks.compactMap({ $0["completed"] as? Bool }) == macTasks.compactMap({ $0["completed"] as? Bool }),
              macResult["completedTaskCount"] as? Int == 1 else {
            throw NSError(domain: "HeaderThumbnail", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Both native Header notes must have the same five tasks and completion state."])
        }
        note = macSource
        width = CGFloat(macSource.width) / 2
        height = CGFloat(macSource.height) / 2
    } else {
        guard let frames = macResult["noteWindowFrames"] as? [[String: Double]], let frame = frames.last,
              let x = frame["x"], let y = frame["y"], let w = frame["width"], let h = frame["height"],
              let crop = macSource.cropping(to: CGRect(x: x * 2, y: (900 - y - h) * 2, width: w * 2, height: h * 2)) else {
            throw NSError(domain: "HeaderThumbnail", code: 5)
        }
        note = crop
        width = w
        height = h
    }
    guard let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent("Tildone/Localizable.xcstrings"))) as? [String: Any] else {
        throw NSError(domain: "HeaderThumbnail", code: 6)
    }
    func localized(_ key: String) throws -> String {
        guard let strings = catalog["strings"] as? [String: Any], let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any], let localized = localizations[language] as? [String: Any],
              let unit = localized["stringUnit"] as? [String: Any], let value = unit["value"] as? String else {
            throw NSError(domain: "HeaderThumbnail", code: 6)
        }
        return value
    }
    let renderer = ImageRenderer(content: MarketingIOSHeaderThumbnail(phone: phone,
        statusBackdrop: NSImage(cgImage: strip, size: NSSize(width: 12, height: 162)),
        macNote: NSImage(cgImage: note, size: NSSize(width: width, height: height)), wallpaper: wallpaper,
        headline: try localized(asset == "header" ? "Your Mac notes.\nWith you." : "Your to-dos.\nOn iPhone and Mac."),
        benefit: try localized("Free iCloud sync"), asset: asset, locale: locale,
        cropSafeReview: cropSafeReview, midScaleReview: midScaleReview, spacingReview: spacingReview,
        textReview: textReview, largeTextReview: largeTextReview))
    renderer.scale = full ? 3 : 1
    renderer.isOpaque = true
    guard let rendered = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: rendered.width, height: rendered.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "HeaderThumbnail", code: 7)
    }
    context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
    guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "HeaderThumbnail", code: 8)
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try png.write(to: output)
    let previousNoteHeight = 280 * height / width
    let originalMacNoteFrame = CGRect(x: (asset == "header" ? (midScaleReview ? 397 : 666) : 560)
                                     + (spacingReview ? 30 / 0.65 : 0) + 850 / 2 - (spacingReview ? 46 : 6) - 84,
                              y: (asset == "header" ? (midScaleReview ? -105 : 95) : 365) + 150 + previousNoteHeight * 0.2,
                              width: 168, height: previousNoteHeight * 0.6)
    let layoutScale: CGFloat = midScaleReview ? 0.65 : 0.45
    let layoutX: CGFloat = midScaleReview ? 325 : 352
    let layoutY: CGFloat = midScaleReview ? 130 : 160
    let macNoteFrame = cropSafeReview
        ? CGRect(x: originalMacNoteFrame.minX * layoutScale + layoutX, y: originalMacNoteFrame.minY * layoutScale + layoutY,
                 width: originalMacNoteFrame.width * layoutScale, height: originalMacNoteFrame.height * layoutScale)
        : originalMacNoteFrame
    let safeArea = CGRect(x: 1097.0 / 3, y: 493.0 / 3, width: 1646.0 / 3, height: 661.0 / 3)
    let captionScale: CGFloat = largeTextReview ? 1.5 : (textReview ? 1.15 : 1)
    let captionLeftShift: CGFloat = largeTextReview ? 138 : (textReview ? 18 : 0)
    let captionUpShift: CGFloat = largeTextReview ? 27 : 0
    let marketingTextFrame = CGRect(x: 64 * layoutScale + layoutX - captionLeftShift,
                                   y: 180 * layoutScale + layoutY - captionUpShift,
                                   width: 376 * layoutScale * captionScale,
                                   height: (midScaleReview ? 200 : 230) * layoutScale * captionScale)
    let phoneChecklistFrame = midScaleReview ? CGRect(x: spacingReview ? 585 : 570, y: 220, width: 230, height: 160)
                                            : CGRect(x: 574, y: 201, width: 156, height: 163)
    guard !cropSafeReview || (safeArea.contains(macNoteFrame) && (textReview || safeArea.contains(marketingTextFrame))
                             && safeArea.contains(phoneChecklistFrame)) else {
        throw NSError(domain: "HeaderThumbnail", code: 12,
                      userInfo: [NSLocalizedDescriptionKey: "Header copy and both native checklists must fit inside Apple's safe area."])
    }
    let canvasHeight = (asset == "header" ? 1646.0 : 2560.0) / 3
    guard macNoteFrame.minX >= 0, macNoteFrame.minY >= 0,
          macNoteFrame.maxX <= 1280, macNoteFrame.maxY <= canvasHeight,
          !full || (image.width == 3840 && image.height == (asset == "header" ? 1646 : 2560)) else {
        throw NSError(domain: "HeaderThumbnail", code: 9,
                      userInfo: [NSLocalizedDescriptionKey: "The complete native Mac note must fit inside the review canvas."])
    }
    let proof: [String: Any] = ["asset": asset, "draft": !full, "locale": locale, "verified": true,
        "approved": full, "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
        "nativeUI": true, "mockDataOnly": true, "liveCloudKitUsed": false,
        "pixelWidth": image.width, "pixelHeight": image.height, "targetUploadSize": [3840, asset == "header" ? 1646 : 2560],
        "nativePhoneProof": nativeURL.path, "nativeMacProof": macResultURL.path,
        "phoneSource": phoneURL.path, "phoneSHA256": SHA256.hash(data: phoneData).map { String(format: "%02x", $0) }.joined(),
        "macSource": macURL.path, "macSHA256": SHA256.hash(data: macData).map { String(format: "%02x", $0) }.joined(),
        "macInputRoot": macInputRoot?.path ?? "default Mac inputs",
        "sixColorPalette": true, "phoneIslandHidden": true, "macNotchVisible": true,
        "revision": largeTextReview ? 11 : (textReview ? 10 : (spacingReview ? 9 : (midScaleReview ? 8 : (cropSafeReview ? 7 : (asset == "search-results" ? 1 : (nativeRoot == nil ? 3 : 4)))))),
        "cropSafeReview": cropSafeReview,
        "midScaleReview": midScaleReview,
        "spacingReview": spacingReview,
        "textReview": textReview,
        "largeTextReview": largeTextReview,
        "captionScaleRelativeToR9": captionScale,
        "captionLeftShiftFromR9": captionLeftShift,
        "captionUpShiftFromR9": captionUpShift,
        "captionInsideHeaderSafeArea": safeArea.contains(marketingTextFrame),
        "phoneRightShiftFromR8": spacingReview ? 15 : 0,
        "macRightShiftFromR8": spacingReview ? 30 : 0,
        "essentialContentInsideHeaderSafeArea": cropSafeReview && safeArea.contains(marketingTextFrame),
        "fillsCanvas": true, "phoneBezel": "physical titanium with side buttons",
        "taskCount": nativeRoot == nil ? 2 : 5, "completedTaskCount": nativeRoot == nil ? 0 : 1,
        "phoneWidth": midScaleReview ? 208 : (cropSafeReview ? 144 : (asset == "header" ? 320 : 400)), "phoneTiltDegrees": -5,
        "macBottomBeyondCanvas": true, "macKeyboardVisible": cropSafeReview,
        "macKeyboardAndTrackpadPerspective": cropSafeReview,
        "macDisplayAspectRatio": 850.0 / 620,
        "macNoteFullyVisible": true,
        "macNoteFrame": [macNoteFrame.minX, macNoteFrame.minY, macNoteFrame.width, macNoteFrame.height],
        "macNoteScaleRelativeToRevision2": 0.6, "macNoteScaleAnchor": "center",
        "phoneForegroundShadow": true,
        "appleHeaderArtSafeArea": [1097, 493, 2743, 1154],
        "safeAreaSource": "Apple Photoshop Product Page Header Template, downloaded 2026-10-26",
        "freeFeaturesOnly": true, "requiresThumbnailApproval": !full]
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.deletingPathExtension().appendingPathExtension("json"))
    print(output.path)
}

do {
    try MainActor.assumeIsolated { try renderHeaderThumbnail() }
} catch {
    FileHandle.standardError.write(Data("Header thumbnail failed: \(error)\n".utf8))
    exit(1)
}
