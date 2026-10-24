#if MARKETING_CAPTURE
import AppKit
import AVFoundation
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

/// Only enumerates and records this process's windows. No screen-recording
/// consent, display capture, microphone, audio, or other apps are requested.
@available(macOS 15, *)
final class MarketingCaptureRecorder: NSObject, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?

    @discardableResult
    func captureImage(windowID: CGWindowID, destination: URL, width: Int, height: Int,
                      auxiliaryExcludingWindowIDs: Set<CGWindowID> = []) async throws -> Int {
        let content = try await SCShareableContent.currentProcess
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw NSError(domain: "MarketingCapture", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "The screenshot canvas is not available."])
        }
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.includeChildWindows = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
        guard image.width == width, image.height == height,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw NSError(domain: "MarketingCapture", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "The screenshot could not be rendered as an opaque RGB image."])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // includeChildWindows already includes the related native NSMenu.
        // A second desktopIndependentWindow capture can resolve the menu's
        // owning canvas, so compositing that result would stamp a miniature
        // canvas over the real menu. Keep the original pixels for visual review.
        var auxiliaryCount = 0
        if !auxiliaryExcludingWindowIDs.isEmpty {
            let popups = content.windows.filter {
                !auxiliaryExcludingWindowIDs.contains($0.windowID) && $0.isOnScreen
                    && $0.windowLayer > window.windowLayer && $0.frame.intersects(window.frame)
                    && $0.frame.width > 5 && $0.frame.height > 5
            }.sorted { $0.windowLayer < $1.windowLayer }
            guard !popups.isEmpty else {
                throw NSError(domain: "MarketingCapture", code: 24,
                              userInfo: [NSLocalizedDescriptionKey: "The real privacy menu popup is not available for capture."])
            }
            auxiliaryCount = popups.count
        }
        guard let opaque = context.makeImage(),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MarketingCapture", code: 12)
        }
        CGImageDestinationAddImage(output, opaque, nil)
        guard CGImageDestinationFinalize(output) else { throw NSError(domain: "MarketingCapture", code: 13) }
        return auxiliaryCount
    }

    func start(windowID: CGWindowID, destination: URL) async throws {
        let content = try await SCShareableContent.currentProcess
        guard let ownWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw NSError(domain: "MarketingCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The capture canvas is not available."])
        }
        let configuration = SCStreamConfiguration()
        configuration.width = 1920
        configuration.height = 1080
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.includeChildWindows = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        configuration.colorSpaceName = CGColorSpace.sRGB
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: ownWindow),
                              configuration: configuration, delegate: nil)
        let file = SCRecordingOutputConfiguration()
        file.outputURL = destination
        file.outputFileType = .mp4
        file.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: file, delegate: self)
        try stream.addRecordingOutput(output)
        self.output = output
        self.stream = stream
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            Swift.Task {
                do { try await stream.startCapture() }
                catch { startContinuation?.resume(throwing: error); startContinuation = nil }
            }
        }
    }

    func stop() async throws {
        guard let stream else { return }
        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            Swift.Task {
                do { try await stream.stopCapture() }
                catch { finishContinuation?.resume(throwing: error); finishContinuation = nil }
            }
        }
        self.stream = nil
        output = nil
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        startContinuation?.resume(); startContinuation = nil
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finishContinuation?.resume(); finishContinuation = nil
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        startContinuation?.resume(throwing: error); startContinuation = nil
        finishContinuation?.resume(throwing: error); finishContinuation = nil
    }
}
#endif
