import Foundation

/// A conservative plan for *approximate beat-hint* starts. It does not know
/// musical downbeats, phrases or key, and does not time-stretch either player.
/// Its timestamps are used by a control-thread scheduler, not sample-accurate
/// Core Audio scheduling. Rejects significant accumulated tempo drift.
struct BeatHintTransition: Equatable, Sendable {
    let sourceCueSeconds: Double
    let targetCueSeconds: Double
    let leadSeconds: Double
    let blendSeconds: Double
    let expectedDriftSeconds: Double
    let beats: Int

    /// Future start is selected from the source grid's *local beat phase*;
    /// multiple-of-four grouping is a UI convenience, NOT a phrase label.
    static func make(source: BeatGridEstimate, target: BeatGridEstimate,
                     sourcePosition: Double, sourceDuration: Double,
                     targetDuration: Double, beats: Int = 8,
                     minimumLead: Double = 0.45,
                     maxDriftSeconds: Double = 0.07) -> BeatHintTransition? {
        guard source.isValid, target.isValid,
              [sourcePosition, sourceDuration, targetDuration, minimumLead,
               maxDriftSeconds].allSatisfy({ $0.isFinite }),
              (4...32).contains(beats), beats.isMultiple(of: 4),
              minimumLead >= 0.15, minimumLead <= 3,
              maxDriftSeconds > 0, maxDriftSeconds <= 0.3,
              sourcePosition >= 0, sourceDuration > sourcePosition,
              targetDuration > target.firstBeatSeconds else { return nil }

        let sourcePeriod = source.beatIntervalSeconds
        let targetPeriod = target.beatIntervalSeconds
        let drift = Double(beats) * abs(sourcePeriod - targetPeriod)
        guard drift <= maxDriftSeconds else { return nil }

        // Require at least 450 ms of scheduling headroom; schedule the next
        // beat from a four-beat grouping. The start has no guaranteed phrase.
        let next = max(0, ceil((sourcePosition + minimumLead - source.firstBeatSeconds) /
                               (sourcePeriod * 4)))
        let cue = source.firstBeatSeconds + next * sourcePeriod * 4
        let lead = cue - sourcePosition
        let length = Double(beats) * sourcePeriod
        guard cue.isFinite, cue >= sourcePosition + minimumLead - 1e-8,
              cue + length + 0.05 < sourceDuration,
              target.firstBeatSeconds + length + drift + 0.05 < targetDuration,
              lead <= 12.0 else { return nil }
        return BeatHintTransition(sourceCueSeconds: cue,
                                  targetCueSeconds: target.firstBeatSeconds,
                                  leadSeconds: lead, blendSeconds: length,
                                  expectedDriftSeconds: drift, beats: beats)
    }
}
