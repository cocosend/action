import Foundation

private final class Signals: @unchecked Sendable {
    private let lock = NSLock()
    private var flags = (started: false, canceled: false)
    func markStarted() { lock.lock(); flags.started = true; lock.unlock() }
    func markCanceled() { lock.lock(); flags.canceled = true; lock.unlock() }
    var started: Bool { lock.lock(); defer { lock.unlock() }; return flags.started }
    var canceled: Bool { lock.lock(); defer { lock.unlock() }; return flags.canceled }
}

@main enum BackgroundWorkTests {
    static func main() async throws {
        let fast = try await BackgroundWork.run { 42 }
        precondition(fast == 42)
        let signals = Signals()
        let parent = Task {
            try await BackgroundWork.run(priority: .userInitiated) {
                signals.markStarted()
                while !Task<Never, Never>.isCancelled {
                    Thread.sleep(forTimeInterval: 0.002)
                }
                signals.markCanceled()
                throw CancellationError()
            }
        }
        var launched = false
        for _ in 0..<150 {
            if signals.started { launched = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(launched, "Detached work did not start")
        parent.cancel()
        var observed = false
        for _ in 0..<150 {
            if signals.canceled { observed = true; break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(observed, "Parent cancellation did not reach worker")
        do {
            _ = try await parent.value
            preconditionFailure("Canceled worker unexpectedly returned success")
        } catch is CancellationError { /* expected */ }
        // Even an already canceled caller must never start a fresh detached
        // waveform/file decode. The preflight check rejects it immediately.
        let canceledBeforeLaunch = Signals()
        let early = Task {
            try await BackgroundWork.run(priority: .utility) {
                canceledBeforeLaunch.markStarted()
                return 100
            }
        }
        early.cancel()
        do {
            _ = try await early.value
            preconditionFailure("Pre-canceled caller unexpectedly returned a value")
        } catch is CancellationError { /* expected */ }
        precondition(!canceledBeforeLaunch.started,
                     "Pre-canceled caller launched expensive detached analysis")

        // Worker failure must be propagated unchanged to the control actor.
        struct ExpectedFailure: Error {}
        do {
            let _: Int = try await BackgroundWork.run { throw ExpectedFailure() }
            preconditionFailure("Worker error was swallowed")
        } catch is ExpectedFailure { /* expected */ }
        print("BackgroundWorkTests PASS — cancellation while active, before launch, and failure propagation")
    }
}
