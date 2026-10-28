import Foundation

@main struct ImportCommitPolicyTests {
    static func main() {
        func allowed(_ expected: UInt64, _ current: UInt64, _ active: Int?, _ deck: Int) -> Bool {
            ImportCommitPolicy.mayCommit(expectedGeneration: expected,
                                         currentGeneration: current,
                                         activeImportDeck: active,
                                         requestedDeck: deck)
        }
        assert(allowed(17, 17, 0, 0))
        assert(!allowed(17, 18, nil, 0), "Switching to pattern must reject in-flight file")
        assert(!allowed(17, 18, 1, 0), "Old deck A copy cannot install onto deck B")
        assert(!allowed(17, 17, 1, 0), "Only the active import slot can commit")
        assert(!allowed(17, 17, 0, -1))
        assert(!allowed(17, 17, 0, 2))
        assert(allowed(UInt64.max, UInt64.max, 1, 1))
        print("ImportCommitPolicyTests PASS — race, switching deck, invalid indices")
    }
}
