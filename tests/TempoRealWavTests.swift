import Foundation

/// Regression test: the real C++ synth+EQ+AutoMix WAV should yield a plausible
/// BPM hint. Runs on Linux/macOS without any iOS SDK or audio hardware.
@main struct TempoRealWavTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Provide WAV path") }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let b = [UInt8](data)
        guard b.count >= 44,
              String(decoding: b[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: b[8..<12], as: UTF8.self) == "WAVE",
              String(decoding: b[36..<40], as: UTF8.self) == "data" else {
            fatalError("Bad test WAV header")
        }
        func u32(_ offset: Int) -> Int {
            Int(b[offset]) | (Int(b[offset + 1]) << 8) |
            (Int(b[offset + 2]) << 16) | (Int(b[offset + 3]) << 24)
        }
        let rate = u32(24)
        guard rate == 48_000, b[22] == 2, b[34] == 16 else {
            fatalError("Test expects stereo 48 kHz signed 16-bit PCM")
        }
        let hop = rate / 100
        let samplePairs = (b.count - 44) / 4
        let bins = samplePairs / hop
        var rms: [Float] = []
        rms.reserveCapacity(bins)
        for window in 0..<bins {
            var sum = 0.0
            for frame in 0..<hop {
                let pos = 44 + (window * hop + frame) * 4
                let l = Int16(bitPattern: UInt16(b[pos]) | (UInt16(b[pos+1]) << 8))
                let r = Int16(bitPattern: UInt16(b[pos+2]) | (UInt16(b[pos+3]) << 8))
                let dl = Double(l) / 32_768, dr = Double(r) / 32_768
                sum += (dl * dl + dr * dr) * 0.5
            }
            rms.append(Float(sqrt(sum / Double(hop))))
        }
        guard let estimate = TempoAnalyzer.estimate(energies: rms, samplesPerSecond: 100),
              abs(estimate.bpm - 138) <= 5,
              estimate.confidence >= 0.45 else {
            fatalError("C++ rendered audio should have ~138 BPM (estimate, not SYNC/beatgrid)")
        }
        let grid = BeatGridAnalyzer.estimate(energies: rms, samplesPerSecond: 100,
                                              tempo: estimate)
        if let grid {
            guard grid.isValid &&
                  abs(60 / grid.beatIntervalSeconds - estimate.bpm) <= estimate.bpm * 0.045 else {
                fatalError("The estimated beat phase must agree with the tempo hint")
            }
            print("C++ WAV beat phase hint: \(grid.firstBeatSeconds)s, interval \(grid.beatIntervalSeconds)s, confidence \(grid.confidence)")
        } else {
            print("C++ WAV beat phase: unavailable (conservative refusal)")
        }
        print("TempoRealWavTests PASS: \(estimate.bpm) BPM, confidence \(estimate.confidence)")
    }
}
