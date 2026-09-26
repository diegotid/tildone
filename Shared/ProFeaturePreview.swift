import SwiftUI

/// Real note components rendered with localized mock content. Mac composes a
/// live hover demonstration over a cached raster; it never edits user notes.
struct ProFeaturePreview: View {
    let feature: ProFeature
    var canvasSize = CGSize(width: 360, height: 360)
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @AppStorage(NoteWindowBackground.opacityStorageKey) private var backgroundOpacity = Double(NoteWindowBackground.defaultAlpha)
    @State private var noteImage: NSImage?
    @State private var animationStart = Date()
    #else
    @State private var preview: Image?
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            GeometryReader { geometry in
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: feature != .blur || reduceMotion)) { context in
                    ProPreviewScene(
                        feature: feature, locale: locale, noteImage: noteImage,
                        elapsedTime: context.date.timeIntervalSince(animationStart),
                        reduceMotion: reduceMotion, canvasSize: canvasSize
                    )
                    .environment(\.locale, locale)
                    .scaleEffect(geometry.size.width / canvasSize.width, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.width * canvasSize.height / canvasSize.width, alignment: .topLeading)
                }
            }
            #else
            if let preview {
                preview.resizable().aspectRatio(contentMode: .fit)
            } else {
                ProPreviewScene(feature: feature, locale: locale)
                    .allowsHitTesting(false)
            }
            #endif
        }
        .aspectRatio(canvasSize.width / canvasSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHidden(true) // The adjacent outcome describes the feature.
        .task(id: renderIdentity) {
            #if os(macOS)
            noteImage = MacProPreviewNote.rasterImage(
                content: ProPreviewContent(feature: feature, locale: locale), locale: locale,
                colorScheme: colorScheme, backgroundOpacity: backgroundOpacity
            )
            animationStart = Date()
            #else
            preview = Self.render(feature: feature, locale: locale, colorScheme: colorScheme)
            #endif
        }
    }

    private var renderIdentity: String {
        #if os(macOS)
        "\(feature.rawValue)-\(locale.identifier)-\(colorScheme)-\(backgroundOpacity)"
        #else
        "\(feature.rawValue)-\(locale.identifier)-\(colorScheme)"
        #endif
    }

    @MainActor
    static func render(feature: ProFeature, locale: Locale, colorScheme: ColorScheme) -> Image? {
        #if os(macOS)
        guard let image = rasterImage(feature: feature, locale: locale, colorScheme: colorScheme) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = rasterImage(feature: feature, locale: locale, colorScheme: colorScheme) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}

#if os(macOS)
import AppKit

extension ProFeaturePreview {
    @MainActor
    static func rasterImage(feature: ProFeature, locale: Locale, colorScheme: ColorScheme,
                            elapsedTime: TimeInterval = 0, reduceMotion: Bool = false,
                            defaults: UserDefaults = .standard,
                            canvasSize: CGSize = CGSize(width: 360, height: 360)) -> NSImage? {
        if feature == .dimming || feature == .gathering {
            // Settings previews contain native material and checkbox views.
            // Capture their actual AppKit hosting surface, rather than asking
            // ImageRenderer to draw unsupported NSViewRepresentable content.
            let scene = ProPreviewScene(feature: feature, locale: locale,
                                        elapsedTime: elapsedTime, reduceMotion: reduceMotion, usesFixedTime: true, canvasSize: canvasSize)
                .defaultAppStorage(defaults)
                .environment(\.locale, locale)
                .environment(\.colorScheme, colorScheme)
            let host = NSHostingView(rootView: scene)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: canvasSize),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: canvasSize)
            host.layoutSubtreeIfNeeded()
            defer { window.close() }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(bitmap)
            return image
        }
        // Capture native note controls first, then use SwiftUI's renderer for
        // blur, opacity, and layout. AppKit cacheDisplay omits those effects.
        guard let noteImage = MacProPreviewNote.rasterImage(
            content: ProPreviewContent(feature: feature, locale: locale), locale: locale,
            colorScheme: colorScheme, backgroundOpacity: Double(NoteWindowBackground.currentAlpha(from: defaults))
        ) else { return nil }
        let renderer = ImageRenderer(content:
            ProPreviewScene(feature: feature, locale: locale, noteImage: noteImage,
                            elapsedTime: elapsedTime, reduceMotion: reduceMotion, usesFixedTime: true, canvasSize: canvasSize)
                .defaultAppStorage(defaults)
                .environment(\.locale, locale)
                .environment(\.colorScheme, colorScheme)
                .frame(width: canvasSize.width, height: canvasSize.height)
        )
        renderer.scale = 2
        return renderer.nsImage
    }
}
#else
import UIKit

extension ProFeaturePreview {
    @MainActor
    static func rasterImage(feature: ProFeature, locale: Locale, colorScheme: ColorScheme) -> UIImage? {
        let renderer = ImageRenderer(content:
            ProPreviewScene(feature: feature, locale: locale)
                .environment(\.locale, locale)
                .environment(\.colorScheme, colorScheme)
                .frame(width: 360, height: 360)
        )
        renderer.scale = 2
        return renderer.uiImage
    }
}
#endif
