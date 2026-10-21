#if MARKETING_CAPTURE
import AppKit
import AVFoundation
import ScreenCaptureKit

/// Only enumerates and records this process's windows. No screen-recording
/// consent, display capture, microphone, audio, or other apps are requested.
@available(macOS 15, *)
final class MarketingCaptureRecorder: NSObject, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?

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
