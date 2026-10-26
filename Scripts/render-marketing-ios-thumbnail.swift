#!/usr/bin/env swift
// Approved screenshot composition. The phone content is a native simulator capture.
import AppKit
import CryptoKit
import SwiftUI

struct MarketingIOSThumbnail: View {
    let capture: NSImage
    let statusBackground: NSImage
    let headline: String
    let subtitle: String
    let asset: String
    let proLabel: String
    let macCapture: NSImage?
    let macWallpaper: NSImage?
    let macBookLayerOnly: Bool
    let deckCapture: NSImage?
    let deckStatusBackground: NSImage?

    private let yellow = Color(red: 1.00, green: 0.94, blue: 0.63)
    private let green = Color(red: 0.73, green: 1.00, blue: 0.72)
    private let blue = Color(red: 0.68, green: 0.82, blue: 0.95)
    private let pink = Color(red: 0.98, green: 0.78, blue: 0.86)
    private let purple = Color(red: 0.84, green: 0.76, blue: 0.96)
    private let orange = Color(red: 0.99, green: 0.84, blue: 0.70)

    private func phone(capture: NSImage, statusBackground: NSImage) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44)
                .fill(.white.opacity(0.32))
                .shadow(color: Color(red: 0.43, green: 0.34, blue: 0.19).opacity(0.15),
                        radius: 18, y: 10)
            RoundedRectangle(cornerRadius: 44)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.3), .white.opacity(0.8)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            ZStack(alignment: .top) {
                Image(nsImage: capture)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 320, height: 320 * 2622 / 1206)
                // Remove only the hardware island, retaining the real status
                // bar and all app pixels. This is artwork, not a UI change.
                Image(nsImage: statusBackground)
                    .resizable()
                    .frame(width: 112, height: 43)
                    .padding(.top, 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 34))
            .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(.white.opacity(0.75), lineWidth: 0.75))
        }
        .frame(width: 342, height: 320 * 2622 / 1206 + 22)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if !macBookLayerOnly {
                Color.white
                // All six shipping note colors form a soft wash around the phone.
                // The headline area stays light, as in the approved composition.
                RadialGradient(colors: [yellow.opacity(0.85), .clear], center: UnitPoint(x: 0, y: 0.57),
                               startRadius: 0, endRadius: 310)
                RadialGradient(colors: [green.opacity(0.62), .clear], center: UnitPoint(x: 0, y: 0.32),
                               startRadius: 0, endRadius: 245)
                RadialGradient(colors: [blue.opacity(0.80), .clear], center: UnitPoint(x: 1, y: 0.46),
                               startRadius: 0, endRadius: 290)
                RadialGradient(colors: [orange.opacity(0.90), .clear], center: .bottomLeading,
                               startRadius: 0, endRadius: 325)
                RadialGradient(colors: [pink.opacity(0.90), .clear], center: UnitPoint(x: 0.48, y: 1),
                               startRadius: 0, endRadius: 280)
                RadialGradient(colors: [purple.opacity(0.85), .clear], center: UnitPoint(x: 1, y: 0.84),
                               startRadius: 0, endRadius: 300)
                VStack(spacing: proLabel.isEmpty ? 15 : 10) {
                    Text(headline)
                        .font(.system(size: asset == "screenshot-2" ? 32 : 36, weight: .medium))
                        .tracking(-1.1)
                        .lineSpacing(-1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(white: 0.10))
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color(white: 0.29))
                    if !proLabel.isEmpty {
                        Text(proLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.65), in: Capsule())
                    }
                }
                .padding(.top, proLabel.isEmpty ? 67 : 50)

                if asset == "screenshot-3", let deckCapture, let deckStatusBackground {
                    let deviceWidth: CGFloat = 270
                    let deviceScale = deviceWidth / 342
                    let deviceHeight = (320 * 2622 / 1206 + 22) * deviceScale
                    // Equal 24pt edge margins; the grid starts 24pt below the
                    // subtitle, and the deck sits in front in the opposite corner.
                    phone(capture: capture, statusBackground: statusBackground)
                        .scaleEffect(deviceScale, anchor: .topLeading)
                        .frame(width: deviceWidth, height: deviceHeight, alignment: .topLeading)
                        .offset(x: -61, y: 208)
                    phone(capture: deckCapture, statusBackground: deckStatusBackground)
                        .scaleEffect(deviceScale, anchor: .topLeading)
                        .frame(width: deviceWidth, height: deviceHeight, alignment: .topLeading)
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.16), radius: 16, x: -6, y: 6)
                        .offset(x: 61, y: 956 - 24 - deviceHeight)
                } else {
                    phone(capture: capture, statusBackground: statusBackground)
                        .padding(.top, 218)
                }
            }
            if let macCapture {
                let insetScale = min(240 / macCapture.size.width, 240 / macCapture.size.height)
                // Zoom into the center top of a MacBook Pro display. The sides
                // and lower laptop extend beyond the artwork; its real note
                // sits right of the visible camera notch inside the screen.
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(.black.opacity(0.78))
                    ZStack {
                        if let macWallpaper {
                            Image(nsImage: macWallpaper)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                        }
                    }
                    .frame(width: 642, height: 492)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .padding(9)
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.06))
                        Rectangle().fill(Color(white: 0.06)).frame(height: 12)
                        Circle().fill(Color(white: 0.16)).frame(width: 4, height: 4).padding(.top, 8)
                    }
                    .frame(width: 106, height: 24)
                    .padding(.top, 8)
                    Image(nsImage: macCapture)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: macCapture.size.width * insetScale,
                               height: macCapture.size.height * insetScale)
                        // The opaque native window crop includes wallpaper
                        // outside its rounded corners. Mask inside that edge.
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                        .shadow(color: .black.opacity(0.2), radius: 14, y: 7)
                        .offset(x: 65, y: 78)
                }
                .frame(width: 660, height: 510)
                .overlay(RoundedRectangle(cornerRadius: 30)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.5)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
                // Cast the foreground display's shadow upward onto the phone.
                .shadow(color: .black.opacity(0.30), radius: 34, y: -18)
                .shadow(color: .black.opacity(0.24), radius: 10, y: -4)
                .offset(y: 574)
            }
        }
        // Extra wallpaper below the video crop lets its MacBook layer sit
        // higher while retaining a full desktop behind the bottom captions.
        .frame(width: 440, height: macBookLayerOnly ? 1156 : 956)
        .clipped()
        .environment(\.colorScheme, .light)
    }
}

@MainActor
func render() throws {
    guard (3...7).contains(CommandLine.arguments.count),
          let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
          let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
          let bytes = NSBitmapImageRep(data: data),
          bytes.pixelsWide == 1206, bytes.pixelsHigh == 2622,
          let strip = bytes.cgImage?.cropping(to: CGRect(x: 8, y: 11, width: 12, height: 162)) else {
        throw NSError(domain: "MarketingThumbnail", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected native-frame.png output.png [locale] [scale] [asset]"])
    }
    let locale = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : "en-US"
    let scale = CommandLine.arguments.count >= 5 ? Double(CommandLine.arguments[4]) ?? 0 : 1
    let asset = CommandLine.arguments.count >= 6 ? CommandLine.arguments[5] : "screenshot-1"
    let macBookLayerOnly = CommandLine.arguments.count == 7 && CommandLine.arguments[6] == "--macbook-layer"
    let deckPath = CommandLine.arguments.count == 7 && !macBookLayerOnly ? CommandLine.arguments[6] : nil
    let languages = ["en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"]
    guard let language = languages[locale], [1.0, 3.0].contains(scale) else {
        throw NSError(domain: "MarketingThumbnail", code: 3)
    }
    let catalogURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Tildone/Localizable.xcstrings")
    let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
    func localized(_ key: String) throws -> String {
        guard let strings = catalog?["strings"] as? [String: Any],
              let entry = strings[key] as? [String: Any],
              let locales = entry["localizations"] as? [String: Any],
              let value = locales[language] as? [String: Any],
              let unit = value["stringUnit"] as? [String: Any],
              unit["state"] as? String == "translated", let text = unit["value"] as? String else {
            throw NSError(domain: "MarketingThumbnail", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Missing approved marketing translation for \(locale)."])
        }
        return text
    }
    let copy: [String: (String, String)] = [
        "screenshot-1": ("Get it off\nyour mind.", "Simple lists. Free iCloud sync with Mac."),
        "screenshot-2": ("On iPhone. On Mac.\nIn sync.", "Free iCloud sync. Same Apple Account."),
        "screenshot-3": ("See your plans\nyour way.", "List, grid or deck. All free."),
        "screenshot-4": ("Find your\nnext thing.", "Search your notes and tasks."),
        "screenshot-5": ("Small steps.\nReal progress.", "Break it down. Keep moving."),
        "screenshot-6": ("Give a thought\nits own space.", "One purchase. iPhone and Mac. No subscription.")
    ]
    guard let keys = copy[asset] else { throw NSError(domain: "MarketingThumbnail", code: 5) }
    let headline = try localized(keys.0)
    let subtitle = try localized(keys.1)
    let proLabel = ["screenshot-5", "screenshot-6"].contains(asset)
        ? try localized("Optional Pro · One-time purchase") : ""
    var macCapture: NSImage?
    var macWallpaper: NSImage?
    if asset == "screenshot-2" {
        let root = catalogURL.deletingLastPathComponent().deletingLastPathComponent()
        let macDirectory = root.appendingPathComponent("Marketing/Preview/Output/screenshots/02/\(locale)")
        let info = try JSONSerialization.jsonObject(with: Data(contentsOf: macDirectory.appendingPathComponent("screenshot-result.json"))) as? [String: Any]
        let imageURL = macDirectory.appendingPathComponent("Tildone-macOS-screenshot-02-\(locale).png")
        guard let frames = info?["noteWindowFrames"] as? [[String: Double]], frames.count == 4,
              let frame = frames.last, let x = frame["x"], let y = frame["y"], let w = frame["width"], let h = frame["height"],
              let sourceData = try? Data(contentsOf: imageURL), let source = NSBitmapImageRep(data: sourceData)?.cgImage,
              let crop = source.cropping(to: CGRect(x: x * 2, y: (900 - y - h) * 2, width: w * 2, height: h * 2)) else {
            throw NSError(domain: "MarketingThumbnail", code: 6)
        }
        macCapture = NSImage(cgImage: crop, size: NSSize(width: w, height: h))
        let wallpaperURL = macDirectory.appendingPathComponent("TildonePreviewStudio.app/Contents/Resources/GoldenGate.png")
        guard let wallpaper = NSImage(contentsOf: wallpaperURL) else {
            throw NSError(domain: "MarketingThumbnail", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "Missing supplied Golden Gate wallpaper."])
        }
        macWallpaper = wallpaper
    }
    var deckCapture: NSImage?
    var deckBackdrop: NSImage?
    var deckSHA256 = ""
    if let deckPath {
        let deckData = try Data(contentsOf: URL(fileURLWithPath: deckPath))
        guard asset == "screenshot-3", let deck = NSImage(data: deckData),
              let pixels = NSBitmapImageRep(data: deckData),
              pixels.pixelsWide == 1206, pixels.pixelsHigh == 2622,
              let strip = pixels.cgImage?.cropping(to: CGRect(x: 8, y: 11, width: 12, height: 162)) else {
            throw NSError(domain: "MarketingThumbnail", code: 8)
        }
        deckCapture = deck
        deckBackdrop = NSImage(cgImage: strip, size: NSSize(width: 12, height: 162))
        deckSHA256 = SHA256.hash(data: deckData).map { String(format: "%02x", $0) }.joined()
    }
    // Preserve the real vertical status-bar backdrop rather than painting a
    // flat patch over the island. The source strip contains no text or icons.
    let backdrop = NSImage(cgImage: strip, size: NSSize(width: 12, height: 162))
    let renderer = ImageRenderer(content: MarketingIOSThumbnail(capture: image, statusBackground: backdrop,
                                                             headline: headline, subtitle: subtitle,
                                                             asset: asset, proLabel: proLabel, macCapture: macCapture,
                                                             macWallpaper: macWallpaper, macBookLayerOnly: macBookLayerOnly,
                                                             deckCapture: deckCapture, deckStatusBackground: deckBackdrop))
    renderer.proposedSize = ProposedViewSize(width: 440, height: macBookLayerOnly ? 1156 : 956)
    renderer.scale = scale
    renderer.isOpaque = !macBookLayerOnly
    guard let rendered = renderer.cgImage,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: rendered.width, height: rendered.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: macBookLayerOnly ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "MarketingThumbnail", code: 2)
    }
    // ImageRenderer can emit 16-bit RGB; upload artwork is explicitly 8-bit sRGB.
    context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
    guard let cgImage = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MarketingThumbnail", code: 2)
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    try png.write(to: output)
    let proof: [String: Any] = [
        "asset": "ios-" + asset, "locale": locale, "proDisclosure": proLabel,
        "nativeMacInset": macCapture != nil,
        "macBookProScreenCrop": macCapture != nil, "macNotchVisible": macCapture != nil,
        "macWallpaper": macWallpaper == nil ? "none" : "supplied macOS Golden Gate",
        "headline": headline, "subtitle": subtitle,
        "pixelWidth": cgImage.width, "pixelHeight": cgImage.height,
        "opaque": renderer.isOpaque, "notePalette": ["yellow", "green", "blue", "orange", "pink", "purple"],
        "source": CommandLine.arguments[1], "sourceSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
        "outputSHA256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
        "twoNativePhoneViews": deckCapture != nil, "nativeDeckSource": deckPath ?? "none",
        "nativeDeckSourceSHA256": deckSHA256, "phoneEdgeMarginPoints": deckCapture == nil ? 49 : 24,
        "macBookLayerOnly": macBookLayerOnly, "nativeAppPixels": true, "hardwareIslandHidden": true, "compositionScale": scale
    ]
    try JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.deletingPathExtension().appendingPathExtension("json"))
    print(CommandLine.arguments[2])
}

do {
    try MainActor.assumeIsolated { try render() }
} catch {
    FileHandle.standardError.write(Data("Screenshot export failed: \(error)\n".utf8))
    exit(1)
}
