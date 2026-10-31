import Foundation

private func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

private func pulses(bpm: Double, offset: Double, seconds: Double = 34,
                    sampleRate: Double = 100) -> [Float] {
    var energies = [Float](repeating: 0.001, count: Int(seconds * sampleRate))
    let beatDuration = 60.0 / bpm
    var beat = 0
    while true {
        let index = Int(((offset + Double(beat) * beatDuration) * sampleRate).rounded())
        guard index + 10 < energies.count else { break }
        for j in 0..<10 {
            energies[index + j] += Float(0.80 * exp(-Double(j) * 0.9))
        }
        // Include musically useful but weaker offbeat hi-hat subdivisions.
        let hatIndex = Int(((offset + (Double(beat) + 0.5) * beatDuration) * sampleRate).rounded())
        if hatIndex + 5 < energies.count {
            for j in 0..<5 { energies[hatIndex + j] += Float(0.15 * exp(-Double(j) * 0.8)) }
        }
        beat += 1
    }
    return energies
}

@main struct BeatGridAnalyzerTests {
    static func main() throws {
        for bpm in [78.0, 96.0, 120.0, 128.0, 145.0, 174.0] {
            for offset in [0.12, 0.24] {
                let input = pulses(bpm: bpm, offset: offset)
                let tempo = TempoEstimate(bpm: bpm, confidence: 0.96)
                guard let grid = BeatGridAnalyzer.estimate(energies: input, samplesPerSecond: 100,
                                                           tempo: tempo) else {
                    fatalError("No beat grid: BPM \(bpm) offset \(offset)")
                }
                let expected = 60.0 / bpm
                let phase = grid.firstBeatSeconds
                let cycError = min(abs(phase - offset),
                                   abs(phase - offset + expected),
                                   abs(phase - offset - expected))
                fputs(String(format: "BPM %.1f offset %.2f -> grid %.2f, phase %.3f, confidence %.2f\n",
                             bpm, offset, 60/grid.beatIntervalSeconds, phase, grid.confidence), stderr)
                check(abs(grid.beatIntervalSeconds - expected) < 0.014,
                      "Period too far from true beat \(bpm)")
                check(cycError < 0.06, "Phase drift too far from \(offset): \(phase)")
                check(grid.isValid, "Invalid metadata")
                let encoded = try JSONEncoder().encode(grid)
                let restored = try JSONDecoder().decode(BeatGridEstimate.self, from: encoded)
                check(restored == grid, "Metadata roundtrip mismatch")
            }
        }
        // At 96 BPM, syncopated offbeats may legitimately fool a BPM
        // detector into 192 BPM. This is a known octave ambiguity; the
        // beatgrid analyzer cannot manufacture certainty about the pulse.
        let ambiguous = pulses(bpm: 96, offset: 0.12)
        if let heuristic = TempoAnalyzer.estimate(energies: ambiguous, samplesPerSecond: 100) {
            let phaseOnly = BeatGridAnalyzer.estimate(energies: ambiguous, samplesPerSecond: 100,
                                                       tempo: heuristic)
            if let phaseOnly {
                check(abs(60 / phaseOnly.beatIntervalSeconds - heuristic.bpm) < 6,
                      "Beat period must remain consistent with accepted tempo estimate")
            }
        }
        let quiet = [Float](repeating: 0, count: 3500)
        let nominal = TempoEstimate(bpm: 128, confidence: 0.9)
        check(BeatGridAnalyzer.estimate(energies: quiet, samplesPerSecond: 100, tempo: nominal) == nil,
              "Do not fabricate beatgrid from silence")
        let weak = TempoEstimate(bpm: 128, confidence: 0.1)
        check(BeatGridAnalyzer.estimate(energies: pulses(bpm: 128, offset: 0.1),
                                        samplesPerSecond: 100, tempo: weak) == nil,
              "Low-confidence BPM must reject beatgrid")
        var seed: UInt64 = 0x390e85ce
        let noise: [Float] = (0..<5000).map { _ in
            seed = seed &* 2862933555777941757 &+ 3037000493
            return Float(seed >> 48) / Float(UInt16.max)
        }
        check(BeatGridAnalyzer.estimate(energies: noise, samplesPerSecond: 100,
                                        tempo: nominal) == nil,
              "Do not fabricate grid from non-periodic noise")
        let malformed = BeatGridEstimate(firstBeatSeconds: .nan,
                                         beatIntervalSeconds: 60.0 / 128, confidence: 0.8)
        check(!malformed.isValid, "Non-finite beat phase must be rejected")
        print("BeatGridAnalyzerTests PASS")
    }
}
