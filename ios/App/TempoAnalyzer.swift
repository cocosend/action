import Foundation

/// A conservative tempo hint, not a beatgrid, phase lock or SYNC claim.
/// The analyzer operates on fixed-size, off-audio-thread energy windows.
struct TempoEstimate: Codable, Equatable, Sendable {
    let bpm: Double
    let confidence: Double

    var isValid: Bool {
        bpm.isFinite && (60...200).contains(bpm) &&
        confidence.isFinite && (0...1).contains(confidence)
    }
}

enum TempoAnalyzer {
    /// Expects RMS/energy samples at a constant (approximately 100 Hz) rate.
    /// Returns nil when the evidence is insufficient or rhythm is ambiguous.
    static func estimate(energies: [Float], samplesPerSecond: Double) -> TempoEstimate? {
        guard samplesPerSecond.isFinite, (30...1000).contains(samplesPerSecond),
              energies.count >= Int(10 * samplesPerSecond),
              energies.count <= Int(240 * samplesPerSecond),
              energies.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }

        let n = energies.count
        // Positive log-energy novelty isolates transients from sustained pads / noise.
        let logEnergy = energies.map { log1p(Double($0) * 20.0) }
        let mean = logEnergy.reduce(0, +) / Double(n)
        var novelty = [Double](repeating: 0, count: n)
        for i in 2..<n {
            // Contrast against a 20–40ms local baseline, preventing a long bass
            // envelope from filling an entire beat with artificial onsets.
            let baseline = 0.65 * logEnergy[i - 2] + 0.35 * logEnergy[i - 1]
            novelty[i] = max(0, logEnergy[i] - baseline)
        }
        let nonzero = novelty.filter { $0 > 0.003 }.count
        guard mean > 0.004, nonzero >= 12 else { return nil }

        // Suppress very faint novelty; normalized clipping prevents one anomalous
        // transient from dominating the complete analysis.
        let maxNovelty = novelty.max() ?? 0
        guard maxNovelty > 0.02 else { return nil }
        let gate = maxNovelty * 0.055
        for i in 0..<n {
            novelty[i] = novelty[i] > gate ? min(1, novelty[i] / maxNovelty) : 0
        }

        // Energy at adjacent lags is a simple tempo score. Search an interval
        // useful for electronic dance music, without asserting the beat phase.
        let minLag = max(2, Int((60.0 * samplesPerSecond / 200.0).rounded()))
        let maxLag = min(n / 4, Int((60.0 * samplesPerSecond / 70.0).rounded()))
        guard maxLag > minLag else { return nil }
        var candidates: [(lag: Int, strength: Double)] = []
        for lag in minLag...maxLag {
            var correlation = 0.0
            var weight = 0.0
            var i = lag
            while i < n {
                let current = novelty[i], previous = novelty[i - lag]
                correlation += current * previous
                weight += 0.5 * (current * current + previous * previous)
                i += 1
            }
            // The energy-normalized score minimizes bias toward short lags.
            // More sophisticated beat phase estimation belongs to beatgrid.
            let score = weight > 0.0001 ? correlation / weight : 0
            if score.isFinite { candidates.append((lag: lag, strength: score)) }
        }
        guard let best = candidates.max(by: { $0.strength < $1.strength }),
              best.strength >= 0.38 else { return nil }
        // In dance music the same phrase often yields a strong score at half
        // tempo. If the half-lag peak is sufficiently coherent, prefer the
        // faster pulse instead of presenting 72 BPM for a 145 BPM track.
        let halfTempoCandidates = candidates.filter {
            abs(Double($0.lag) - Double(best.lag) * 0.5) <= 1.5 &&
            $0.strength >= best.strength * 0.60 && $0.strength > 0.43
        }
        let selected = halfTempoCandidates.max(by: { $0.strength < $1.strength }) ?? best

        // Check non-overlapping 10+ second regions for tempo stability; reject
        // if a candidate matches only a brief fill or a single repeated sample.
        let blocks = max(1, n / Int(10 * samplesPerSecond))
        var goodBlocks = 0
        for b in 0..<blocks {
            let start = b * n / blocks
            let end = (b + 1) * n / blocks
            var corr = 0.0, energy = 0.0
            if start + selected.lag < end {
                for i in (start + selected.lag)..<end {
                    corr += novelty[i] * novelty[i - selected.lag]
                    energy += 0.5 * (novelty[i] * novelty[i] + novelty[i - selected.lag] * novelty[i - selected.lag])
                }
            }
            if energy > 0.05 && corr / energy > 0.27 { goodBlocks += 1 }
        }
        guard goodBlocks >= max(1, (blocks + 1) / 2) else { return nil }
        let secondsPerBeat = Double(selected.lag) / samplesPerSecond
        let bpm = 60 / secondsPerBeat
        let score = selected.strength * (Double(goodBlocks) / Double(blocks))
        // This confidence is an internal heuristic, never show it as a
        // statistical probability or claim exact phase synchronization.
        let estimate = TempoEstimate(bpm: (bpm * 10).rounded() / 10,
                                     confidence: min(0.99, max(0, score)))
        return estimate.isValid ? estimate : nil
    }
}
