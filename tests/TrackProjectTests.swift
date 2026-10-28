import Foundation

@main
struct TrackProjectTests {
    static func main() throws {
        let fresh = TrackProject()
        precondition(fresh.isValid)
        precondition(fresh.velocity.count == 2)
        precondition(fresh.velocity[0].count == 4)
        precondition(fresh.velocity[1][0][2][14] == 106)
        precondition(fresh.velocity[0][0][0][0] == 112)
        precondition(fresh.velocity[0][1][1][2] == 90)
        precondition(fresh.velocity[0][2][0][4] == 0)
        precondition(fresh.velocity[0][3][0][14] == 112)

        var session = fresh
        session.bpm = 148
        session.swing = 0.25
        session.crossfader = 0.3
        session.bank = [2, 3]
        session.deckGain = [0.8, 0.6]
        session.velocity[1][3][1][7] = 45
        session.deckEQ[1][0] = -3.5
        session.deckEQ[0][2] = 6.0
        session.deckDelay = [0.25, 0.4]
        session.patternMute[0][1] = true
        session.patternSolo[1][2] = true
        let encoded = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(TrackProject.self, from: encoded)
        precondition(restored.isValid)
        precondition(restored.bpm == 148)
        precondition(restored.bank == [2, 3])
        precondition(restored.velocity[1][3][1][7] == 45)
        precondition(restored.deckEQ[1][0] == -3.5)
        precondition(restored.deckEQ[0][2] == 6.0)
        precondition(restored.deckDelay == [0.25, 0.4])
        precondition(restored.patternMute[0][1] && restored.patternSolo[1][2])

        // The legacy 0.2.0 project schema lacks EQ. Migrate without losing patterns.
        var oldPayload = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        oldPayload.removeValue(forKey: "deckEQ")
        oldPayload.removeValue(forKey: "deckDelay")
        oldPayload.removeValue(forKey: "patternMute")
        oldPayload.removeValue(forKey: "patternSolo")
        let oldData = try JSONSerialization.data(withJSONObject: oldPayload)
        let oldProject = try JSONDecoder().decode(TrackProject.self, from: oldData)
        precondition(oldProject.isValid && oldProject.bank == [2, 3])
        precondition(oldProject.deckEQ == [[0, 0, 0], [0, 0, 0]])
        precondition(oldProject.deckDelay == [0, 0])
        precondition(oldProject.patternMute == [[false, false, false], [false, false, false]])
        precondition(oldProject.patternSolo == [[false, false, false], [false, false, false]])
        precondition(oldProject.velocity[1][3][1][7] == 45)

        let manifest = ImportedAudioStore()
        precondition(manifest.decks.count == 2)
        let imported = ImportedAudio(fileName: "A_UUID.wav", title: "Night Circuit", duration: 120)
        precondition(imported.isValid)
        precondition(!ImportedAudio(fileName: "../secret.wav", title: "bad", duration: 20).isValid)
        precondition(!ImportedAudio(fileName: "", title: "bad", duration: 20).isValid)
        precondition(!ImportedAudio(fileName: "valid.wav", title: "bad", duration: .nan).isValid)
        let manifestData = try JSONEncoder().encode(ImportedAudioStore(decks: [imported, nil]))
        let decodedManifest = try JSONDecoder().decode(ImportedAudioStore.self, from: manifestData)
        precondition(decodedManifest.decks[0] == imported && decodedManifest.decks[1] == nil)
        // Existing imported-file manifests (pre-tempo) must still decode.
        let legacyImported = Data(#"{"fileName":"legacy.wav","title":"Legacy","duration":60.0}"#.utf8)
        let migratedImported = try JSONDecoder().decode(ImportedAudio.self, from: legacyImported)
        precondition(migratedImported.isValid && migratedImported.tempo == nil && migratedImported.beatGrid == nil)
        let withTempo = ImportedAudio(fileName: "estimate.wav", title: "Analyzed", duration: 90,
                                      tempo: TempoEstimate(bpm: 129.8, confidence: 0.78))
        precondition(withTempo.isValid)
        let restoredTempo = try JSONDecoder().decode(ImportedAudio.self,
                                               from: JSONEncoder().encode(withTempo))
        precondition(restoredTempo == withTempo)
        let loop = FileLoopPlan(startSeconds: 2.1, endSeconds: 6.1, beats: 8)
        let looped = ImportedAudio(fileName: "loop.wav", title: "Loop", duration: 40,
                                   hotCues: [Double?](repeating: nil, count: 8), loop: loop)
        precondition(looped.isValid)
        let restoredLoop = try JSONDecoder().decode(ImportedAudio.self,
                                                   from: JSONEncoder().encode(looped))
        precondition(restoredLoop == looped && restoredLoop.loop == loop)
        precondition(!ImportedAudio(fileName: "badloop.wav", title: "bad", duration: 40,
                 loop: FileLoopPlan(startSeconds: 35, endSeconds: 45, beats: 8)).isValid)
        let grid = BeatGridEstimate(firstBeatSeconds: 0.16, beatIntervalSeconds: 60.0 / 129.8,
                                    confidence: 0.71)
        let withGrid = ImportedAudio(fileName: "grid.wav", title: "Grid Hint", duration: 75,
                                     tempo: withTempo.tempo, beatGrid: grid)
        precondition(withGrid.isValid)
        let roundtripGrid = try JSONDecoder().decode(ImportedAudio.self,
                                                  from: JSONEncoder().encode(withGrid))
        precondition(roundtripGrid == withGrid)
        precondition(!ImportedAudio(fileName: "bad.wav", title: "Bad Grid", duration: 75,
                 tempo: withTempo.tempo,
                 beatGrid: BeatGridEstimate(firstBeatSeconds: 0.1, beatIntervalSeconds: 0.7,
                                            confidence: 0.8)).isValid)
        precondition(!ImportedAudio(fileName: "tempo.wav", title: "invalid", duration: 60,
                 tempo: TempoEstimate(bpm: .infinity, confidence: 0.8)).isValid)

        session.deckDelay = [0.4, 0.9]
        precondition(!session.isValid)
        session.deckDelay = [0.25, 0.4]
        session.bpm = Double.nan
        precondition(!session.isValid)
        session.bpm = 148
        session.bank = [0, 4]
        precondition(!session.isValid)
        session.bank = [0, 1]
        session.velocity[0][0][0][0] = -1
        precondition(!session.isValid)

        // Required fields are intentionally mandatory; corrupted documents cannot silently
        // replace the user's project with a partial, mismatched pattern.
        do {
            _ = try JSONDecoder().decode(TrackProject.self, from: Data(#"{"schemaVersion":1,"bpm":132}"#.utf8))
            preconditionFailure("Partial project must not decode successfully")
        } catch DecodingError.keyNotFound {
            // Correctly rejected.
        }
    }
}
