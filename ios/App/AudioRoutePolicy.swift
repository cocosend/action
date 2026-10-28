import Foundation

/// Pure route-safety decisions, independent of AVFAudio and the UI actor.
/// The sample rate is NOT a proxy for headphones/Bluetooth presence: an
/// unplug event is safety-critical even if both routes happen to use 48 kHz.
enum AudioRoutePolicy {
    enum Change: Equatable {
        case outputDisconnected
        case routeUnavailable
        case outputConnected
        case configurationChanged
    }

    struct Decision: Equatable {
        let pausePlayback: Bool
        let rebuildEngine: Bool
    }

    static func decision(change: Change, wasPlaying: Bool,
                         previousRate: Double, currentRate: Double) -> Decision {
        let lostOutput = change == .outputDisconnected || change == .routeUnavailable
        return Decision(
            pausePlayback: lostOutput && wasPlaying,
            rebuildEngine: shouldRebuildEngine(previousRate: previousRate,
                                               currentRate: currentRate)
        )
    }

    /// Legacy wrapper kept for portability of older model tests.
    static func shouldPauseForOutputLoss(wasOutputDisconnected: Bool,
                                         wasPlaying: Bool) -> Bool {
        wasOutputDisconnected && wasPlaying
    }

    static func shouldRebuildEngine(previousRate: Double, currentRate: Double) -> Bool {
        guard previousRate.isFinite, currentRate.isFinite,
              previousRate >= 8_000, currentRate >= 8_000 else { return true }
        return abs(previousRate - currentRate) > 1.0
    }
}
