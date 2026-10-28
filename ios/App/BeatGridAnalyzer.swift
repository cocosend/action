import Foundation

/// An offline, approximate beat-phase hint, not a sync clock or a phrase analysis.
/// Time zero means the beginning of the decoded file. It is safe to persist.
struct BeatGridEstimate: Codable, Equatable, Sendable {
    let firstBeatSeconds: Double
    let beatIntervalSeconds: Double
    let confidence: Double

    var isValid: Bool {
        firstBeatSeconds.isFinite && beatIntervalSeconds.isFinite && confidence.isFinite &&
        (0.29...0.87).contains(beatIntervalSeconds) &&
        firstBeatSeconds >= 0 && firstBeatSeconds < beatIntervalSeconds &&
        (0...1).contains(confidence)
    }

    func beatTime(_ index: Int) -> Double {
        firstBeatSeconds + Double(index) * beatIntervalSeconds
    }
}

enum BeatGridAnalyzer {
    /// RMS windows at constant spacing. Detects beat position only after a
    /// conservative BPM analyzer has accepted the tempo. No phase/phrase SYNC.
    /// Never call from a realtime audio thread.
    static func estimate(energies: [Float], samplesPerSecond: Double,
                         tempo: TempoEstimate) -> BeatGridEstimate? {
        guard tempo.isValid, tempo.confidence >= 0.45,
              samplesPerSecond.isFinite, (30...1000).contains(samplesPerSecond),
              energies.count >= Int(10 * samplesPerSecond),
              energies.count <= Int(240 * samplesPerSecond),
              energies.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }

        // Use an early excerpt to avoid assuming perfect tempo throughout a
        // full song. The returned beat period is approximate, and downstream
        // callers must not use it to time-stretch or silently SYNC a file.
        let count = min(energies.count, Int(18 * samplesPerSecond))
        var novelty = [Double](repeating: 0, count: count)
        let logValues = energies.prefix(count).map { log1p(Double($0) * 20) }
        var peak = 0.0
        for i in 2..<count {
            let baseline = logValues[i - 2] * 0.65 + logValues[i - 1] * 0.35
            let change = max(0, logValues[i] - baseline)
            novelty[i] = change
            peak = max(peak, change)
        }
        guard peak > 0.025 else { return nil }
        let threshold = peak * 0.06
        var events: [(time: Double, weight: Double)] = []
        for i in 2..<(count - 2) {
            let energy = novelty[i]
            // Keep only true peaks, separated by about 20ms so that a
            // 100ms kick decay cannot masquerade as 4 independent beats.
            if energy >= threshold && energy >= novelty[i - 1] && energy > novelty[i + 1] &&
                energy >= novelty[i - 2] && energy > novelty[i + 2] {
                events.append((Double(i) / samplesPerSecond, min(1, energy / peak)))
            }
        }
        guard events.count >= 12 else { return nil }
        let total = events.reduce(0) { $0 + $1.weight }
        guard total > 2.0 else { return nil }

        // Refine the initial lag-quantized tempo by searching ±3%; the
        // autocorrelation input has only 10ms resolution at 100Hz and 174 BPM
        // otherwise drifts visibly over a 30-second waveform.
        let nominalPeriod = 60.0 / tempo.bpm
        let phaseBins = max(24, Int(samplesPerSecond * nominalPeriod))
        let candidates = 65
        var bestScore = -Double.infinity
        var bestPhase = 0.0
        var bestPeriod = nominalPeriod
        for pIndex in 0..<candidates {
            let period = nominalPeriod * (0.97 + 0.06 * Double(pIndex) / Double(candidates - 1))
            var bins = [Double](repeating: 0, count: phaseBins)
            for event in events {
                let phase = event.time.truncatingRemainder(dividingBy: period) / period
                let bin = Int((phase * Double(phaseBins)).rounded()) % phaseBins
                bins[bin] += event.weight
            }
            // Circular peak neighborhood tolerates slight onset extraction
            // jitter while preserving the accuracy of the phase estimate.
            for j in 0..<phaseBins {
                let score = bins[j] + 0.70 * (bins[(j + phaseBins - 1) % phaseBins] +
                                              bins[(j + 1) % phaseBins]) +
                            0.22 * (bins[(j + phaseBins - 2) % phaseBins] +
                                    bins[(j + 2) % phaseBins])
                if score > bestScore {
                    bestScore = score
                    bestPeriod = period
                    bestPhase = Double(j) / Double(phaseBins) * period
                }
            }
        }
        // 'confidence' describes localized transient concentration, not a
        // statistical probability nor a guarantee of stable beatgrid phase.
        let concentration = bestScore / total
        guard concentration.isFinite, concentration >= 0.23 else { return nil }
        let result = BeatGridEstimate(firstBeatSeconds: min(bestPeriod - 0.000001, bestPhase),
                                      beatIntervalSeconds: bestPeriod,
                                      confidence: min(0.99, concentration * min(1, tempo.confidence / 0.55)))
        return result.isValid ? result : nil
    }
}
