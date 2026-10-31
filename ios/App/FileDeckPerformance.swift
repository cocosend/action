import Foundation

/// Value-level validation for a file deck; safe to test without Apple SDK.
/// Hot cues are absolute file seconds; they do not pretend to be beat sync.
enum FileDeckPerformance {
    static let slotCount = 8
    static func validPosition(_ seconds: Double, duration: Double) -> Bool {
        seconds.isFinite && duration.isFinite && duration > 0 &&
            seconds >= 0 && seconds < duration
    }

    static func setCue(_ imported: ImportedAudio, slot: Int, seconds: Double) -> ImportedAudio? {
        guard imported.isValid, (0..<slotCount).contains(slot),
              validPosition(seconds, duration: imported.duration) else { return nil }
        var cues = imported.hotCues ?? [Double?](repeating: nil, count: slotCount)
        cues[slot] = seconds
        return replacingCues(imported, cues)
    }

    static func clearCue(_ imported: ImportedAudio, slot: Int) -> ImportedAudio? {
        guard imported.isValid, (0..<slotCount).contains(slot) else { return nil }
        var cues = imported.hotCues ?? [Double?](repeating: nil, count: slotCount)
        cues[slot] = nil
        return replacingCues(imported, cues)
    }

    static func cuePosition(_ imported: ImportedAudio, slot: Int) -> Double? {
        guard (0..<slotCount).contains(slot) else { return nil }
        return imported.hotCues?[slot]
    }

    static func seekFrame(seconds: Double, sampleRate: Double, length: Int64) -> Int64? {
        guard seconds.isFinite, sampleRate.isFinite, sampleRate > 0,
              length > 0, seconds >= 0, seconds * sampleRate < Double(length) else { return nil }
        let frame = Int64((seconds * sampleRate).rounded(.down))
        return min(length - 1, max(0, frame))
    }

    private static func replacingCues(_ imported: ImportedAudio, _ cues: [Double?]) -> ImportedAudio? {
        let replacement = ImportedAudio(fileName: imported.fileName, title: imported.title,
                                        duration: imported.duration, tempo: imported.tempo,
                                        beatGrid: imported.beatGrid,
                                        manuallyAdjustedGrid: imported.manuallyAdjustedGrid,
                                        hotCues: cues, loop: imported.loop)
        return replacement.isValid ? replacement : nil
    }
}
