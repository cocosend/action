import Foundation

/// Prevents a completed asynchronous file copy from republishing a deck source
/// that was replaced while disk I/O was still in flight.
enum ImportCommitPolicy {
    static func mayCommit(expectedGeneration: UInt64, currentGeneration: UInt64,
                          activeImportDeck: Int?, requestedDeck: Int) -> Bool {
        (0..<2).contains(requestedDeck) &&
        expectedGeneration == currentGeneration &&
        activeImportDeck == requestedDeck
    }
}
