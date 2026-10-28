import Foundation
@main struct AnalysisMergePolicyTests {
    static func main() {
        let old = ImportedAudio(fileName: "original-uuid.wav", title: "A", duration: 201)
        let updatedCues = FileDeckPerformance.setCue(old, slot: 7, seconds: 91.4)!
        let tempo = TempoEstimate(bpm: 128, confidence: 0.7)
        let grid = BeatGridEstimate(firstBeatSeconds: 0.25,
                                    beatIntervalSeconds: 60 / 128, confidence: 0.65)
        let merged = AnalysisMergePolicy.merge(original: old, current: updatedCues,
                                                estimated: tempo, grid: grid)
        precondition(merged != nil && merged!.isValid)
        precondition(merged?.hotCues?[7] == 91.4)
        precondition(merged?.tempo == tempo && merged?.beatGrid == grid)
        precondition(AnalysisMergePolicy.merge(original: old,
            current: ImportedAudio(fileName: "replacement.wav", title: "B", duration: 201),
            estimated: tempo, grid: grid) == nil)
        let manuallyAdjusted = BeatGridEditor.corrected(old, bpm: 96,
                                                        firstBeatSeconds: 0.3)!
        precondition(AnalysisMergePolicy.merge(original: old, current: manuallyAdjusted,
                                                estimated: tempo, grid: grid) == nil)
        let weak = TempoEstimate(bpm: 128, confidence: 0.2)
        precondition(AnalysisMergePolicy.merge(original: old, current: old,
                                                estimated: weak, grid: grid) == nil)
        precondition(AnalysisMergePolicy.merge(original: old, current: old,
                  estimated: tempo,
                  grid: BeatGridEstimate(firstBeatSeconds: 0.1,
                     beatIntervalSeconds: 0.7, confidence: 0.8)) == nil)
        print("AnalysisMergePolicyTests PASS")
    }
}
