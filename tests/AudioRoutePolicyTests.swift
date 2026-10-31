import Foundation

@main enum AudioRoutePolicyTests {
    static func main() {
        precondition(AudioRoutePolicy.shouldPauseForOutputLoss(
            wasOutputDisconnected: true, wasPlaying: true))
        precondition(!AudioRoutePolicy.shouldPauseForOutputLoss(
            wasOutputDisconnected: false, wasPlaying: true))
        precondition(!AudioRoutePolicy.shouldPauseForOutputLoss(
            wasOutputDisconnected: true, wasPlaying: false))

        // Unplugging wired headphones or Bluetooth can retain the SAME 48kHz
        // sample rate. That must pause playback rather than route it to speaker.
        let unplug = AudioRoutePolicy.decision(change: .outputDisconnected,
            wasPlaying: true, previousRate: 48_000, currentRate: 48_000)
        precondition(unplug == .init(pausePlayback: true, rebuildEngine: false))
        let noRoute = AudioRoutePolicy.decision(change: .routeUnavailable,
            wasPlaying: true, previousRate: 48_000, currentRate: 48_000)
        precondition(noRoute == unplug)
        let connected = AudioRoutePolicy.decision(change: .outputConnected,
            wasPlaying: true, previousRate: 48_000, currentRate: 48_000)
        precondition(connected == .init(pausePlayback: false, rebuildEngine: false))
        // Opening a route is NOT an authorization to resume playback.
        let disconnectedWhilePaused = AudioRoutePolicy.decision(change: .outputDisconnected,
            wasPlaying: false, previousRate: 48_000, currentRate: 48_000)
        precondition(disconnectedWhilePaused == .init(pausePlayback: false, rebuildEngine: false))
        let rateChanged = AudioRoutePolicy.decision(change: .configurationChanged,
            wasPlaying: true, previousRate: 44_100, currentRate: 48_000)
        precondition(rateChanged == .init(pausePlayback: false, rebuildEngine: true))
        let both = AudioRoutePolicy.decision(change: .outputDisconnected,
            wasPlaying: true, previousRate: 44_100, currentRate: 48_000)
        precondition(both == .init(pausePlayback: true, rebuildEngine: true))
        precondition(AudioRoutePolicy.shouldRebuildEngine(previousRate: .nan, currentRate: 48_000))
        precondition(AudioRoutePolicy.shouldRebuildEngine(previousRate: 48_000, currentRate: 0))
        print("AudioRoutePolicyTests PASS — same-rate headphone safety, missing output, recovery, rate change")
    }
}
