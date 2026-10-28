import Foundation
@main struct TempoCompatibilityTests {
    static func main() {
        func t(_ bpm: Double, _ confidence: Double=0.7) -> TempoEstimate {
            TempoEstimate(bpm: bpm, confidence: confidence)
        }
        precondition(TempoCompatibility.compare(nil, t(128)) == .unknown)
        precondition(TempoCompatibility.compare(t(128,0.2), t(128)) == .unknown)
        if case .close(let diff) = TempoCompatibility.compare(t(128), t(129)) {
            precondition(diff < 1)
        } else { preconditionFailure("close") }
        precondition(TempoCompatibility.compare(t(96), t(192)) == .octaveAmbiguous)
        if case .mismatch(let delta) = TempoCompatibility.compare(t(122), t(150)) {
            precondition(delta > 18)
        } else { preconditionFailure("mismatch") }
        precondition(TempoCompatibility.compare(t(120,0), t(120,0)) == .close(deltaPercent: 0))
        precondition(TempoCompatibility.compare(t(120), t(Double.nan)) == .unknown)
        print("TempoCompatibilityTests PASS")
    }
}
