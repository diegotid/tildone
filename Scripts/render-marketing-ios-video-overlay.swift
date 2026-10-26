#!/usr/bin/env swift
import AppKit
import SwiftUI

struct MarketingVideoOverlay: View {
    let caption: String
    let disclosure: String
    let companionIntro: Bool
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            LinearGradient(stops: [
                .init(color: (companionIntro ? Color.black : Color.white).opacity(0), location: 0),
                .init(color: companionIntro ? .black.opacity(0.30) : .white.opacity(0.8), location: 0.55),
                .init(color: companionIntro ? .black.opacity(0.46) : .white, location: 0.72),
                .init(color: companionIntro ? .black.opacity(0.56) : .white, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 640)
            VStack(spacing: 22) {
                Text(caption)
                    .font(.system(size: 64, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(companionIntro ? Color.white : Color(white: 0.12))
                    .padding(.horizontal, 28)
                if !disclosure.isEmpty {
                    Text(disclosure)
                        .font(.system(size: 40, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(companionIntro ? Color.white : Color(white: 0.18))
                        .padding(.horizontal, 28)
                }
            }
            .frame(maxWidth: 822)
            .padding(.bottom, 150)
        }
        .frame(width: 886, height: 1920)
        .environment(\.colorScheme, .light)
    }
}

@MainActor
func render() throws {
    guard CommandLine.arguments.count == 5 else { throw NSError(domain: "VideoOverlay", code: 1) }
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    let locale = CommandLine.arguments[2]
    let key = CommandLine.arguments[3]
    let mode = CommandLine.arguments[4]
    guard ["pro", "free", "companion", "none"].contains(mode) else {
        throw NSError(domain: "VideoOverlay", code: 5)
    }
    let language = ["en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"][locale] ?? "en"
    let catalogURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tildone/Localizable.xcstrings")
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
    func localized(_ key: String) throws -> String {
        guard let entries = root?["strings"] as? [String: Any], let entry = entries[key] as? [String: Any],
              let locales = entry["localizations"] as? [String: Any], let value = locales[language] as? [String: Any],
              let unit = value["stringUnit"] as? [String: Any], let text = unit["value"] as? String else {
            if language == "en" { return key }
            throw NSError(domain: "VideoOverlay", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing video translation: \(key)"])
        }
        return text
    }
    let disclosure = mode == "none" ? "" : try localized(
        mode == "pro" ? "Optional Pro · One-time purchase" : "Free iCloud sync with Mac.")
    let content = try MarketingVideoOverlay(caption: localized(key),
        disclosure: disclosure, companionIntro: mode == "companion")
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let rendered = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: 886, height: 1920, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "VideoOverlay", code: 3)
    }
    context.draw(rendered, in: CGRect(x: 0, y: 0, width: 886, height: 1920))
    guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VideoOverlay", code: 4)
    }
    try png.write(to: output)
}
do {
    try MainActor.assumeIsolated { try render() }
} catch {
    FileHandle.standardError.write(Data("Video overlay export failed: \(error)\n".utf8))
    exit(1)
}
