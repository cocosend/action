import Foundation
@main enum BeatHintTransitionTests {
    static func main() {
        let g = BeatGridEstimate(firstBeatSeconds: 0.12,
                                 beatIntervalSeconds: 0.5, confidence: 0.77)
        let t = BeatGridEstimate(firstBeatSeconds: 0.22,
                                 beatIntervalSeconds: 0.5008, confidence: 0.83)
        let plan = BeatHintTransition.make(source: g, target: t,
            sourcePosition: 23, sourceDuration: 240, targetDuration: 230)!
        precondition(abs(plan.sourceCueSeconds - 24.12) < 1e-8)
        precondition(abs(plan.targetCueSeconds - 0.22) < 1e-9)
        precondition(abs(plan.blendSeconds - 4.0) < 1e-8)
        precondition(plan.expectedDriftSeconds < 0.007)
        precondition(plan.leadSeconds > 0.45)
        precondition(BeatHintTransition.make(source: g, target: t,
            sourcePosition: 239, sourceDuration: 240, targetDuration: 230) == nil)
        precondition(BeatHintTransition.make(source: g, target: t,
            sourcePosition: .nan, sourceDuration: 240, targetDuration: 230) == nil)
        precondition(BeatHintTransition.make(source: g, target: t,
            sourcePosition: 23, sourceDuration: 240, targetDuration: 230, beats: 3) == nil)
        let mismatch = BeatGridEstimate(firstBeatSeconds: 0.1,
                                       beatIntervalSeconds: 60/130, confidence: 0.7)
        precondition(BeatHintTransition.make(source: g, target: mismatch,
            sourcePosition: 23, sourceDuration: 240, targetDuration: 230) == nil)
        let nearEnd = BeatGridEstimate(firstBeatSeconds: 0.0,
                                      beatIntervalSeconds: 0.5, confidence: 0)
        precondition(BeatHintTransition.make(source: nearEnd, target: nearEnd,
            sourcePosition: 22.0, sourceDuration: 26, targetDuration: 240) == nil)
        for beats in [4,8,16,32] {
            let p = BeatHintTransition.make(source: g, target: t,
                sourcePosition: 23, sourceDuration: 240, targetDuration: 230,
                beats: beats, maxDriftSeconds: 0.15)!
            precondition(abs(p.blendSeconds - Double(beats)*0.5) < 1e-9)
            precondition(p.expectedDriftSeconds <= 0.15)
        }
        print("BeatHintTransitionTests PASS — headroom, drift, duration, invalid input")
    }
}
