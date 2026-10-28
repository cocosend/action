import Foundation
@main struct TimedBlendPlanTests {
    static func main() {
        precondition(TimedBlendPlan(start: 0, target: 1, seconds: 4) != nil)
        precondition(TimedBlendPlan(start: -1, target: 1, seconds: 4) == nil)
        precondition(TimedBlendPlan(start: .nan, target: 1, seconds: 4) == nil)
        precondition(TimedBlendPlan(start: 0.4, target: 0.4, seconds: 4) == nil)
        precondition(TimedBlendPlan(start: 0, target: 1, seconds: 121) == nil)
        precondition(TimedBlendPlan.approximateSeconds(bpm: .nan, bars: 2) == nil)
        precondition(TimedBlendPlan.approximateSeconds(bpm: 120, bars: 2) == 4)
        let a = TimedBlendPlan(start: 0.2, target: 1, seconds: 5)!
        let b = TimedBlendPlan(start: 0.8, target: 0, seconds: 5)!
        precondition(abs(a.crossfader(at: -5) - 0.2) < 1e-9)
        precondition(abs(a.crossfader(at: 2.5) - 0.6) < 1e-9)
        precondition(a.crossfader(at: 6) == 1)
        precondition(b.crossfader(at: 5) == 0)
        precondition(abs(a.fraction(at: 0.001) - 0) < 0.00001)
        var old = a.crossfader(at: 0)
        for i in 1...5000 {
            let x = a.crossfader(at: Double(i)/1000)
            precondition(x >= old && x <= 1 && x >= 0)
            old = x
        }
        print("TimedBlendPlanTests PASS")
    }
}
