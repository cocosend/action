import AVFAudio
import Foundation

/// Decodes only a bounded excerpt on a background worker. Never call from
/// the Core Audio callback or from the UI actor. Produces conservative BPM
/// and optional approximate phase hints, NOT a sync or phrase analysis.
enum AudioTempoExtractor {
    /// A single bounded file read produces both tempo and an optional
    /// approximate first-beat phase; neither authorizes real file SYNC.
    static func analyze(_ url: URL) throws -> (tempo: TempoEstimate?, beatGrid: BeatGridEstimate?) {
        let file = try AVAudioFile(forReading: url,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate.isFinite, sampleRate >= 8_000,
              file.length >= AVAudioFramePosition(sampleRate * 10),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: 4_096) else { return (nil, nil) }
        let windowFrames = max(64, Int((sampleRate / 100).rounded()))
        let maxFrames = min(Int(file.length), Int(sampleRate * 180))
        var energies: [Float] = []
        energies.reserveCapacity(maxFrames / windowFrames + 1)
        var framesRead = 0
        var energySum: Double = 0
        var energyCount = 0
        while framesRead < maxFrames {
            if Task<Never, Never>.isCancelled { return (nil, nil) }
            try file.read(into: buffer,
                          frameCount: AVAudioFrameCount(min(4_096, maxFrames - framesRead)))
            let count = Int(buffer.frameLength)
            guard count > 0, let channels = buffer.floatChannelData else { break }
            let stereo = buffer.format.channelCount > 1
            for i in 0..<count {
                let left = Double(channels[0][i])
                let right = stereo ? Double(channels[1][i]) : left
                if !left.isFinite || !right.isFinite { return (nil, nil) }
                energySum += 0.5 * (left * left + right * right)
                energyCount += 1
                if energyCount == windowFrames {
                    energies.append(Float(sqrt(energySum / Double(energyCount))))
                    energyCount = 0
                    energySum = 0
                }
            }
            framesRead += count
        }
        let rate = sampleRate / Double(windowFrames)
        let tempo = TempoAnalyzer.estimate(energies: energies, samplesPerSecond: rate)
        let beatGrid = tempo.flatMap {
            BeatGridAnalyzer.estimate(energies: energies, samplesPerSecond: rate, tempo: $0)
        }
        return (tempo, beatGrid)
    }
}
