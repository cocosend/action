import Foundation

/// Safe reconciliation of a completed background tempo/beatgrid task against
/// a deck whose Hot Cues may have changed during the analysis. Never silently
/// replace a manually corrected tempo/grid or a different imported file.
enum AnalysisMergePolicy {
    static func merge(original: ImportedAudio, current: ImportedAudio,
                      estimated: TempoEstimate, grid: BeatGridEstimate?) -> ImportedAudio? {
        guard original.isValid, current.isValid, estimated.isValid,
              estimated.confidence >= 0.45,
              original.fileName == current.fileName,
              original.duration == current.duration,
              original.tempo == current.tempo,
              original.beatGrid == current.beatGrid,
              original.manuallyAdjustedGrid == current.manuallyAdjustedGrid,
              current.manuallyAdjustedGrid != true else { return nil }
        // A user may modify only cue positions while analysis runs. Preserve
        // current metadata instead of the original snapshot's cue array.
        let updated = ImportedAudio(fileName: current.fileName, title: current.title,
            duration: current.duration, tempo: estimated, beatGrid: grid,
            manuallyAdjustedGrid: current.manuallyAdjustedGrid,
            hotCues: current.hotCues, loop: current.loop)
        return updated.isValid ? updated : nil
    }
}
