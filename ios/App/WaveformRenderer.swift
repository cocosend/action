import Foundation
import AVFAudio

/// Pixel/paint data only. Peaks and five band energies come from decoded
/// audio samples, not an animated mock, random colors or separated stems.
/// Bands are approximate real frequency energy (5 cascaded crossover bands),
/// never a claim of FFT precision or vocal/instrument separation.
struct SpectralWaveform: Sendable {
    let peaks: [Float]
    let bands: [Float] // flattened, 5 bands per peak bin: bass to high
    static func empty(bins: Int = 180) -> SpectralWaveform {
        SpectralWaveform(peaks: Array(repeating: 0, count: bins),
                         bands: Array(repeating: 0, count: bins * 5))
    }
}

/// Offline waveform analysis. NEVER call from Core Audio render callback.
/// C++ analysis is stream-based and bounded in memory independent of track
/// length; file decode and pattern render both run on a background task.
enum WaveformRenderer {
    static let binCount = 180

    static func pattern(_ project: TrackProject, deck: Int) -> SpectralWaveform {
        guard (0..<2).contains(deck), let core = tb_create(48_000) else {
            return .empty()
        }
        defer { tb_destroy(core) }
        tb_set_bpm(core, project.bpm)
        tb_set_swing(core, Float(project.swing))
        tb_set_crossfader(core, deck == 0 ? 0 : 1)
        tb_set_master_gain(core, 0.9)
        tb_set_deck_enabled(core, Int32(1-deck), 0)
        tb_select_bank(core, Int32(deck), Int32(project.bank[deck]))
        for voice in 0..<3 {
            tb_set_pattern_voice_mute(core, Int32(deck), Int32(voice),
                                      project.patternMute[deck][voice] ? 1 : 0)
            tb_set_pattern_voice_solo(core, Int32(deck), Int32(voice),
                                      project.patternSolo[deck][voice] ? 1 : 0)
        }
        for bank in 0..<4 {
            for voice in 0..<3 {
                for step in 0..<16 {
                    tb_set_velocity_bank(core, Int32(deck), Int32(bank), Int32(voice), Int32(step),
                                         Int32(project.velocity[deck][bank][voice][step]))
                }
            }
        }
        tb_set_playing(core, 1)
        let frameCount = Int(4 * 4 * 60 / project.bpm * 48_000)
        guard let analysis = tb_spectral_create(48_000, UInt64(frameCount), UInt32(binCount)) else {
            return .empty()
        }
        defer { tb_spectral_destroy(analysis) }
        var left = Array(repeating: Float.zero, count: 512)
        var right = Array(repeating: Float.zero, count: 512)
        var rendered = 0
        while rendered < frameCount {
            if Task.isCancelled { return .empty() }
            let amount = min(512, frameCount - rendered)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    tb_render(core, l.baseAddress, r.baseAddress, amount)
                    _ = tb_spectral_push(analysis, l.baseAddress, r.baseAddress, amount)
                }
            }
            rendered += amount
        }
        return collect(analysis)
    }

    static func audioFile(_ url: URL) throws -> SpectralWaveform {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let total = Int(file.length)
        guard total > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                       frameCapacity: 4096),
              let analysis = tb_spectral_create(file.processingFormat.sampleRate,
                                                UInt64(total), UInt32(binCount)) else {
            return .empty()
        }
        defer { tb_spectral_destroy(analysis) }
        var readFrames = 0
        while readFrames < total {
            if Task.isCancelled { return .empty() }
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, total-readFrames)))
            let count = Int(buffer.frameLength)
            if count == 0 { break }
            guard let channels = buffer.floatChannelData else { break }
            let second = buffer.format.channelCount > 1 ? channels[1] : channels[0]
            _ = tb_spectral_push(analysis, channels[0], second, count)
            readFrames += count
        }
        return collect(analysis)
    }

    private static func collect(_ analysis: OpaquePointer) -> SpectralWaveform {
        var peaks = Array(repeating: Float.zero, count: binCount)
        var bands = Array(repeating: Float.zero, count: binCount * 5)
        let succeeded = peaks.withUnsafeMutableBufferPointer { p in
            bands.withUnsafeMutableBufferPointer { b in
                tb_spectral_finish(analysis, p.baseAddress, b.baseAddress, UInt32(binCount)) != 0
            }
        }
        return succeeded ? SpectralWaveform(peaks: peaks, bands: bands) : .empty()
    }
}
