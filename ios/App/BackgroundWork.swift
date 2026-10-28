import Foundation

/// A structured cancellation boundary for CPU/disk work that must not execute
/// on the SwiftUI/main actor. A bare `Task.detached` survives cancellation of
/// its parent; this helper propagates cancellation and waits for the worker
/// to finish before the caller can publish a stale result.
enum BackgroundWork {
    static func run<Result: Sendable>(
        priority: TaskPriority = .utility,
        operation: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        // A canceled caller must not schedule expensive disk/PCM work.
        try Task<Never, Never>.checkCancellation()
        let worker = Task.detached(priority: priority) {
            try Task<Never, Never>.checkCancellation()
            let result = try operation()
            try Task<Never, Never>.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler {
            let output = try await worker.value
            // A worker can finish just before caller cancellation. Do not
            // publish its result into a now-obsolete view/controller task.
            try Task<Never, Never>.checkCancellation()
            return output
        } onCancel: {
            worker.cancel()
        }
    }
}
