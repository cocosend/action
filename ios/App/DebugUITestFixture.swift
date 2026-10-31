#if DEBUG
import AVFAudio
import Foundation

/// Deterministic, self-owned audio for the iOS simulator's end-to-end UI test.
/// Never runs in ordinary launches, Release builds or on a connected user file.
/// The seeded files exercise the same AVAudioFile import manifest/player path as
/// a user-owned audio file without requiring the iOS Files picker in CI.
enum DebugUITestFixture {
    static let launchArgument = "--mixauto-ui-seeded"

    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        do { try install() }
        catch { assertionFailure("UI audio fixture failed: \(error)") }
    }

    private static func install() throws {
        let folder = ImportedAudioStore.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rate = 48_000.0
        let duration = 12.0
        let count = AVAudioFrameCount(rate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            throw NSError(domain: "MixAutoUITestFixture", code: 1)
        }
        var store = ImportedAudioStore()
        for deck in 0..<2 {
            let name = "mixauto-uitest-\(deck == 0 ? "a" : "b").caf"
            let url = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  let pcm = buffer.floatChannelData else {
                throw NSError(domain: "MixAutoUITestFixture", code: 2)
            }
            buffer.frameLength = count
            let frequency = deck == 0 ? 220.0 : 330.0
            for i in 0..<Int(count) {
                let seconds = Double(i) / rate
                let beat = seconds.truncatingRemainder(dividingBy: 0.5)
                let kickEnvelope = exp(-beat * 24.0)
                let tone = Float(0.08 * sin(2 * .pi * frequency * seconds) +
                                 0.20 * kickEnvelope * sin(2 * .pi * 70.0 * seconds))
                pcm[0][i] = tone
                pcm[1][i] = tone * (deck == 0 ? 0.96 : 0.91)
            }
            let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
            store.decks[deck] = ImportedAudio(fileName: name,
                 title: "CI Deck \(deck == 0 ? "A" : "B") · ORIGINAL SYNTHETIC AUDIO",
                 duration: duration,
                 tempo: TempoEstimate(bpm: 120, confidence: 0.95),
                 beatGrid: BeatGridEstimate(firstBeatSeconds: 0, beatIntervalSeconds: 0.5,
                                             confidence: 0.95))
        }
        try store.save()
    }
}
#endif
