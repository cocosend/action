import Foundation

/// Explicitly timed crossfade of *already playing files*. This is a linear
/// time schedule with smoothstep easing, NOT beat/phrase sync or time stretch.
/// The caller operates controls off the realtime audio callback.
struct TimedBlendPlan: Equatable, Sendable {
    let startPosition: Double
    let targetPosition: Double
    let seconds: Double

    init?(start: Double, target: Double, seconds: Double) {
        guard start.isFinite, target.isFinite, seconds.isFinite,
              (0...1).contains(start), (0...1).contains(target),
              (0.5...120).contains(seconds), start != target else { return nil }
        startPosition = start
        targetPosition = target
        self.seconds = seconds
    }

    func fraction(at elapsed: Double) -> Double {
        guard elapsed.isFinite else { return 0 }
        let x = min(1, max(0, elapsed / seconds))
        return x * x * (3 - 2 * x)
    }

    func crossfader(at elapsed: Double) -> Double {
        startPosition + (targetPosition - startPosition) * fraction(at: elapsed)
    }

    /// UI-only BPM-based duration helper; never presented as precise beat sync.
    static func approximateSeconds(bpm: Double, bars: Int) -> Double? {
        guard bpm.isFinite, (70...200).contains(bpm), (1...8).contains(bars) else { return nil }
        return 4 * Double(bars) * 60 / bpm
    }
}
