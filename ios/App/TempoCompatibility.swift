import Foundation

/// A *warning* model for two unwarped imported files, not harmonic or phrase
/// compatibility. Tempo information is uncertain unless manually confirmed.
enum TempoCompatibility: Equatable, Sendable {
    case unknown
    case close(deltaPercent: Double)
    case octaveAmbiguous
    case mismatch(deltaPercent: Double)

    static func compare(_ a: TempoEstimate?, _ b: TempoEstimate?) -> Self {
        guard let a, let b, a.isValid, b.isValid,
              (a.confidence >= 0.45 || a.confidence == 0),
              (b.confidence >= 0.45 || b.confidence == 0) else { return .unknown }
        let delta = abs(a.bpm - b.bpm) / max(a.bpm, b.bpm) * 100
        if delta <= 1.5 { return .close(deltaPercent: delta) }
        let low = min(a.bpm, b.bpm), high = max(a.bpm, b.bpm)
        if abs(2 * low - high) / high < 0.015 { return .octaveAmbiguous }
        return .mismatch(deltaPercent: delta)
    }

    var text: String {
        switch self {
        case .unknown: return "BPM match unknown — timed blend only"
        case .close(let delta): return String(format: "BPM near (%.1f%%) — phase not synced", delta)
        case .octaveAmbiguous: return "Half/double tempo ambiguity — check grid manually"
        case .mismatch(let delta): return String(format: "BPM differ by %.1f%% — no time stretch", delta)
        }
    }
}
