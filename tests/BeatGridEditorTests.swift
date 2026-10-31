import Foundation

@main struct BeatGridEditorTests {
    static func main() throws {
        let original = ImportedAudio(fileName: "test-original.wav", title: "Untitled", duration: 200,
            tempo: TempoEstimate(bpm: 192.1, confidence: 0.62))
        precondition(original.isValid)
        // User corrects offbeat snare octave ambiguity from 192 to 96 BPM.
        let corrected = BeatGridEditor.corrected(original, bpm: 96, firstBeatSeconds: 0.235)
        precondition(corrected?.isValid == true)
        precondition(corrected?.tempo?.bpm == 96)
        precondition(corrected?.beatGrid?.confidence == 0)
        precondition(corrected?.manuallyAdjustedGrid == true)
        precondition(original.tempo?.bpm == 192.1, "Original value must not mutate")
        let restored = try JSONDecoder().decode(ImportedAudio.self,
                                                from: JSONEncoder().encode(corrected!))
        precondition(restored == corrected)
        precondition(abs(restored.beatGrid!.firstBeatSeconds - 0.235) < 0.00001)
        precondition(BeatGridEditor.corrected(original, bpm: .nan, firstBeatSeconds: 0.2) == nil)
        precondition(BeatGridEditor.corrected(original, bpm: 20, firstBeatSeconds: 0.2) == nil)
        precondition(BeatGridEditor.corrected(original, bpm: 300, firstBeatSeconds: 0.2) == nil)
        precondition(BeatGridEditor.corrected(original, bpm: 120, firstBeatSeconds: -1) == nil)
        precondition(BeatGridEditor.corrected(original, bpm: 120, firstBeatSeconds: 201) == nil)
        // Editing metadata on a manually un-analyzed file is explicit, not
        // a fabricated BPM/automatic phase estimate.
        let noTempo = ImportedAudio(fileName: "no-tempo.wav", title: "No analysis", duration: 120)
        precondition(BeatGridEditor.corrected(noTempo, bpm: 128,
                                               firstBeatSeconds: 0.13)?.isValid == true)
        print("BeatGridEditorTests PASS")
    }
}
