import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

func pulses(bpm: Double, duration: Double = 36, sampleRate: Double = 100,
            withSnare: Bool = true) -> [Float] {
    let n = Int(duration * sampleRate)
    var e = [Float](repeating: 0.002, count: n)
    let interval = 60 * sampleRate / bpm
    var beat = 0
    while Int(Double(beat) * interval) + 8 < n {
        let base = Int((Double(beat) * interval).rounded())
        let kick: Float = 0.8
        for i in 0..<8 {
            e[base + i] += kick * exp(-Float(i) * 0.8)
        }
        if withSnare && beat % 2 == 1 {
            e[base] += 0.14
        }
        beat += 1
    }
    return e
}

@main struct TempoAnalyzerTests {
    static func main() {
        for bpm in [78.0, 96.0, 120.0, 128.0, 145.0, 174.0] {
            let input = pulses(bpm: bpm)
            guard let estimated = TempoAnalyzer.estimate(energies: input, samplesPerSecond: 100) else {
                fatalError("Failed to estimate consistent beat @ \(bpm)")
            }
            print("\(bpm): BPM=\(estimated.bpm), confidence=\(estimated.confidence)")
            check(abs(estimated.bpm - bpm) < 2.8, "Wrong tempo for \(bpm): \(estimated.bpm)")
            check(estimated.confidence > 0.38, "Confidence too low")
        }
        check(TempoAnalyzer.estimate(energies: Array(repeating: 0, count: 3000), samplesPerSecond: 100) == nil,
              "Silence must not produce fake BPM")
        check(TempoAnalyzer.estimate(energies: pulses(bpm: 120, duration: 5), samplesPerSecond: 100) == nil,
              "Short files must not receive confident BPM")
        let broken = [Float](repeating: .nan, count: 3000)
        check(TempoAnalyzer.estimate(energies: broken, samplesPerSecond: 100) == nil,
              "NaN input must be rejected")
        // A deterministic non-periodic envelope must not invent a track tempo.
        var seed: UInt64 = 0x982d54b2
        let noise = (0..<4200).map { _ -> Float in
            seed = seed &* 2862933555777941757 &+ 3037000493
            return Float(seed >> 48) / Float(UInt16.max)
        }
        check(TempoAnalyzer.estimate(energies: noise, samplesPerSecond: 100) == nil,
              "Non-rhythmic random envelope must not produce strong BPM")
        print("TempoAnalyzerTests PASS")
    }
}
