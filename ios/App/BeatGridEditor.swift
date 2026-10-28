import Foundation

/// Pure value transformation used by the controller, never called from
/// the audio render callback. A manual choice is NOT algorithmic confidence.
enum BeatGridEditor {
    /// Returns a replacement value; caller must persist transactionally
    /// before publishing to the active deck. Applies no transport changes.
    static func corrected(_ imported: ImportedAudio,
                          bpm: Double, firstBeatSeconds: Double) -> ImportedAudio? {
        guard imported.isValid, bpm.isFinite, firstBeatSeconds.isFinite,
              (70...200).contains(bpm), firstBeatSeconds >= 0,
              firstBeatSeconds <= imported.duration else { return nil }
        let period = 60.0 / bpm
        // The first-beat phase is always stored within one period. The
        // editor may accept absolute file time to help align long intros.
        let phase = firstBeatSeconds.truncatingRemainder(dividingBy: period)
        // 0.0 indicates manual knowledge, not a measured probability.
        let grid = BeatGridEstimate(firstBeatSeconds: phase,
                                    beatIntervalSeconds: period, confidence: 0)
        let selectedTempo = TempoEstimate(bpm: bpm, confidence: 0)
        let edited = ImportedAudio(fileName: imported.fileName, title: imported.title,
                                   duration: imported.duration, tempo: selectedTempo,
                                   beatGrid: grid, manuallyAdjustedGrid: true,
                                   hotCues: imported.hotCues, loop: imported.loop)
        return edited.isValid ? edited : nil
    }
}
