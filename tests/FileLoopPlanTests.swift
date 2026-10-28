import Foundation
@main enum FileLoopPlanTests {
    static func main() throws {
        let grid = BeatGridEstimate(firstBeatSeconds: 0.10, beatIntervalSeconds: 0.5, confidence: 0.7)
        for beats in [4,8,16] {
            let plan = FileLoopPlan.make(grid: grid, near: 4.30, duration: 120.0, beats: beats)!
            precondition(abs(plan.startSeconds - 4.10) < 1e-7)
            precondition(abs(plan.endSeconds - (4.10 + Double(beats)*0.5)) < 1e-7)
            let (start,length) = plan.pcmRange(sampleRate: 48000, totalFrames: 120*48000)!
            precondition(start == 196800)
            precondition(length == UInt32(Double(beats)*0.5*48000))
            let decoded = try JSONDecoder().decode(FileLoopPlan.self, from: JSONEncoder().encode(plan))
            precondition(plan == decoded)
        }
        precondition(FileLoopPlan.make(grid: grid, near: 119, duration: 120, beats: 8) == nil)
        precondition(FileLoopPlan.make(grid: grid, near: .nan, duration: 120, beats: 8) == nil)
        precondition(FileLoopPlan.make(grid: grid, near: 4, duration: 120, beats: 17) == nil)
        precondition(FileLoopPlan(startSeconds: 10, endSeconds: 9, beats: 4).isValid(duration: 120) == false)
        precondition(FileLoopPlan(startSeconds: 0, endSeconds: 40, beats: 8).isValid(duration: 120) == false)
        precondition(FileLoopPlan(startSeconds: 1, endSeconds: 3, beats: 8).pcmRange(sampleRate: .nan, totalFrames: 120*48000) == nil)
        print("FileLoopPlanTests PASS — 4/8/16 beats, PCM bounds, persistence, invalid cases")
    }
}
