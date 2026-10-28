import Foundation

@main struct FileDeckPerformanceTests {
    static func main() throws {
        let original = ImportedAudio(fileName: "safe.wav", title: "A", duration: 120.5,
                                     tempo: TempoEstimate(bpm: 120, confidence: 0.75),
                                     beatGrid: BeatGridEstimate(firstBeatSeconds: 0.1,
                                        beatIntervalSeconds: 0.5, confidence: 0.6))
        precondition(original.isValid)
        var current = original
        for i in 0..<8 {
            guard let next = FileDeckPerformance.setCue(current, slot: i,
                            seconds: Double(i) * 4.0 + 0.25) else { preconditionFailure("Set cue") }
            current = next
        }
        precondition(current.hotCues?.count == 8)
        precondition(current.hotCues?[7] == 28.25)
        precondition(original.hotCues == nil, "Must not mutate source")
        precondition(FileDeckPerformance.setCue(current, slot: 8, seconds: 4) == nil)
        precondition(FileDeckPerformance.setCue(current, slot: -1, seconds: 4) == nil)
        precondition(FileDeckPerformance.setCue(current, slot: 0, seconds: 120.5) == nil)
        precondition(FileDeckPerformance.setCue(current, slot: 0, seconds: .nan) == nil)
        precondition(FileDeckPerformance.setCue(current, slot: 0, seconds: -.infinity) == nil)
        precondition(FileDeckPerformance.clearCue(current, slot: 8) == nil)
        current = FileDeckPerformance.clearCue(current, slot: 1)!
        precondition(current.hotCues?[1] == nil)
        precondition(current.hotCues?[0] == 0.25)
        precondition(FileDeckPerformance.cuePosition(current, slot: 7) == 28.25)
        precondition(FileDeckPerformance.cuePosition(current, slot: 1) == nil)
        precondition(FileDeckPerformance.seekFrame(seconds: 2.5, sampleRate: 48000,
                                                  length: 48000 * 12) == 120000)
        precondition(FileDeckPerformance.seekFrame(seconds: 12, sampleRate: 48000,
                                                  length: 48000 * 12) == nil)
        precondition(FileDeckPerformance.seekFrame(seconds: -1, sampleRate: 48000,
                                                  length: 48000 * 12) == nil)
        precondition(FileDeckPerformance.seekFrame(seconds: .infinity, sampleRate: 48000,
                                                  length: 48000 * 12) == nil)
        let roundTrip = try JSONDecoder().decode(ImportedAudio.self,
                                from: JSONEncoder().encode(current))
        precondition(current == roundTrip)
        precondition(roundTrip.tempo == original.tempo)
        precondition(roundTrip.beatGrid == original.beatGrid)
        let legacy = try JSONDecoder().decode(ImportedAudio.self,
            from: Data(#"{"fileName":"old.wav","title":"Old","duration":150}"#.utf8))
        precondition(legacy.hotCues == nil && legacy.isValid)
        print("FileDeckPerformanceTests PASS")
    }
}
