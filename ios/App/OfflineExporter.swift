import AVFAudio
import AudioToolbox
import Foundation

/// Renders a new, independent C++ core offline into a genuine stereo 16-bit WAV.
/// This is pattern rendering, NOT capture of a live DJ performance or input file.
enum OfflineExporter {
    static func renderPatternMix(_ project: TrackProject, seconds: Int = 16) throws -> URL {
        guard project.isValid, (1...180).contains(seconds) else {
            throw NSError(domain: "TrackBuilderExport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid export project or duration."])
        }
        let rate: Double = 48_000
        guard let core = tb_create(rate),
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024),
              let channels = buffer.floatChannelData else {
            throw NSError(domain: "TrackBuilderExport", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to initialize offline audio buffers."])
        }
        defer { tb_destroy(core) }
        tb_set_bpm(core, project.bpm)
        tb_set_swing(core, Float(project.swing))
        tb_set_crossfader(core, Float(project.crossfader))
        tb_set_master_gain(core, Float(project.masterGain))
        for deck in 0..<2 {
            tb_set_deck_gain(core, Int32(deck), Float(project.deckGain[deck]))
            tb_set_deck_filter(core, Int32(deck), Float(project.deckFilter[deck]))
            tb_set_deck_delay(core, Int32(deck), Float(project.deckDelay[deck]))
            for band in 0..<3 {
                tb_set_deck_eq(core, Int32(deck), Int32(band), Float(project.deckEQ[deck][band]))
            }
            tb_select_bank(core, Int32(deck), Int32(project.bank[deck]))
            for bank in 0..<4 {
                for voice in 0..<3 {
                    for step in 0..<16 {
                        tb_set_velocity_bank(core, Int32(deck), Int32(bank), Int32(voice),
                            Int32(step), Int32(project.velocity[deck][bank][voice][step]))
                    }
                }
            }
        }
        tb_set_playing(core, 1)

        let exports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MixAutoPro-Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let filename = "TrackBuilder-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).wav"
        let url = exports.appendingPathComponent(filename)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        var remaining = seconds * Int(rate)
        while remaining > 0 {
            let frames = min(remaining, Int(buffer.frameCapacity))
            tb_render(core, channels[0], channels[1], frames)
            buffer.frameLength = AVAudioFrameCount(frames)
            try file.write(from: buffer)
            remaining -= frames
        }
        return url
    }
}
