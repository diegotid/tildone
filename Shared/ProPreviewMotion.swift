import Foundation

/// A calm eight-second pointer loop. Rendering tests can sample exact phases
/// without running timers or interacting with a real note.
enum ProPreviewMotion {
    static func pointerProgress(at elapsedTime: TimeInterval) -> Double {
        let phase = max(0, elapsedTime).truncatingRemainder(dividingBy: 8)
        if phase < 1 { return 0 }
        if phase < 2.4 { return smoothStep((phase - 1) / 1.4) }
        if phase < 5 { return 1 }
        if phase < 6.4 { return 1 - smoothStep((phase - 5) / 1.4) }
        return 0
    }

    static func revealProgress(at elapsedTime: TimeInterval) -> Double {
        min(1, max(0, (pointerProgress(at: elapsedTime) - 0.3) / 0.24))
    }

    private static func smoothStep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}
