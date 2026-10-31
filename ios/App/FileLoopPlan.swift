import Foundation

/// Saved loop bounds are precise PCM seconds derived from an accepted grid.
/// Loop boundaries are beat hints, NOT a detected musical phrase or bar.
struct FileLoopPlan: Codable, Equatable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
    let beats: Int

    func isValid(duration: Double) -> Bool {
        duration.isFinite && duration > 0 &&
        startSeconds.isFinite && endSeconds.isFinite &&
        startSeconds >= 0 && endSeconds > startSeconds &&
        endSeconds <= duration && beats > 0 && beats <= 16 &&
        beats.isMultiple(of: 4) && endSeconds - startSeconds <= 16.0
    }

    static func make(grid: BeatGridEstimate, near seconds: Double,
                     duration: Double, beats: Int) -> Self? {
        guard grid.isValid, seconds.isFinite, duration.isFinite,
              seconds >= 0, seconds < duration,
              [4, 8, 16].contains(beats) else { return nil }
        let period = grid.beatIntervalSeconds
        let index = max(0, floor((seconds - grid.firstBeatSeconds) / period))
        let start = grid.firstBeatSeconds + index * period
        let end = start + period * Double(beats)
        let plan = FileLoopPlan(startSeconds: start, endSeconds: end, beats: beats)
        return plan.isValid(duration: duration) ? plan : nil
    }

    func pcmRange(sampleRate: Double, totalFrames: Int64) -> (Int64, UInt32)? {
        guard sampleRate.isFinite, sampleRate >= 8_000 && sampleRate <= 192_000,
              totalFrames > 0, isValid(duration: Double(totalFrames)/sampleRate) else { return nil }
        // Floor start and end into source PCM sample coordinates; the loop
        // repeats precisely the same buffer without a per-loop UI timer.
        let start = Int64((startSeconds * sampleRate).rounded())
        let end = min(totalFrames, Int64((endSeconds * sampleRate).rounded()))
        let length = end - start
        guard start >= 0, length >= 1024, length <= 192_000 * 16,
              length <= Int64(UInt32.max) else { return nil }
        return (start, UInt32(length))
    }
}
