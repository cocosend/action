import AVFAudio
import AudioToolbox
import Foundation

/// A heap-allocated, single-producer/single-consumer PCM ring. The AVAudio
/// engine mixer tap only copies samples to this preallocated C++ ring: zero
/// allocation, zero blocking, zero file I/O in the real-time callback.
private final class CaptureRingRef: @unchecked Sendable {
    let ring: OpaquePointer
    init?(capacityFrames: Int = 262_144) {
        guard let pointer = tb_capture_create(capacityFrames) else { return nil }
        ring = pointer
    }
    deinit { tb_capture_destroy(ring) }
    func stop() { tb_capture_stop(ring) }
    var active: Bool { tb_capture_active(ring) != 0 }
    var available: Int { tb_capture_available(ring) }
    var inFlight: UInt32 { tb_capture_inflight(ring) }
    var dropped: UInt64 { tb_capture_dropped(ring) }
}

struct LiveRecordingResult: Sendable {
    let fileURL: URL
    let durationSeconds: Double
    let droppedFrames: UInt64
}

/// Records actual *master mixer* output (file decks and patterns, plus EQ,
/// crossfader and gains) to a 16-bit PCM WAV; not the offline pattern render.
/// Assumes start/stop from main actor; worker owns all writing and conversion.
@MainActor final class LiveMixRecorder {
    private let bridge: CaptureRingRef
    private let mixer: AVAudioMixerNode
    private let format: AVAudioFormat
    private var tapInstalled = false
    private var stopped = false

    init(mixer: AVAudioMixerNode,
         onComplete: @escaping @MainActor (Result<LiveRecordingResult, Error>) -> Void) throws {
        let sourceFormat = mixer.outputFormat(forBus: 0)
        guard sourceFormat.channelCount == 2,
              sourceFormat.commonFormat == .pcmFormatFloat32,
              !sourceFormat.isInterleaved,
              sourceFormat.sampleRate > 0,
              let bridge = CaptureRingRef() else {
            throw NSError(domain: "MixAutoRecord", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Hardware mixer must supply non-interleaved stereo float32."])
        }
        self.mixer = mixer
        self.format = sourceFormat
        self.bridge = bridge

        // Call never performs disk I/O, touches controllers or dispatches work.
        mixer.installTap(onBus: 0, bufferSize: 2048, format: sourceFormat) { [bridge] pcm, _ in
            guard let channels = pcm.floatChannelData, pcm.frameLength > 0 else { return }
            _ = tb_capture_push(bridge.ring, channels[0], channels[1], Int(pcm.frameLength))
        }
        tapInstalled = true

        let rate = sourceFormat.sampleRate
        DispatchQueue(label: "com.artss.mixauto.master-wav-writer", qos: .utility).async { [bridge] in
            let outcome: Result<LiveRecordingResult, Error>
            do {
                let exportDir = FileManager.default.urls(for: .documentDirectory,
                    in: .userDomainMask)[0].appendingPathComponent("MixAutoPro-Recordings",
                    isDirectory: true)
                try FileManager.default.createDirectory(at: exportDir,
                    withIntermediateDirectories: true)
                let path = exportDir.appendingPathComponent("MixAuto-Live-\(UUID().uuidString).wav")
                do {
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatLinearPCM),
                        AVSampleRateKey: rate,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false
                    ]
                    let output = try AVAudioFile(forWriting: path, settings: settings,
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                                        frameCapacity: 2048),
                          let channels = buffer.floatChannelData else {
                        throw NSError(domain: "MixAutoRecord", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Cannot allocate recording write buffer"])
                    }
                    var totalFrames = 0
                    while bridge.active || bridge.available > 0 || bridge.inFlight > 0 {
                        let count = tb_capture_pop(bridge.ring, channels[0], channels[1],
                                                   Int(buffer.frameCapacity))
                        if count == 0 {
                            // Sleeping on utility *writer*, never on audio callback.
                            Thread.sleep(forTimeInterval: 0.008)
                            continue
                        }
                        buffer.frameLength = AVAudioFrameCount(count)
                        try output.write(from: buffer)
                        totalFrames += count
                    }
                    // Empty WAV isn't a successful recording.
                    guard totalFrames > 0 else {
                        throw NSError(domain: "MixAutoRecord", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Recording contained no audio frames"])
                    }
                    outcome = .success(LiveRecordingResult(
                        fileURL: path, durationSeconds: Double(totalFrames) / rate,
                        droppedFrames: bridge.dropped))
                } catch {
                    try? FileManager.default.removeItem(at: path)
                    throw error
                }
            } catch { outcome = .failure(error) }
            Task { @MainActor in onComplete(outcome) }
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        // Remove tap before shutting down capture; the callback retains its
        // CaptureRingRef so no freed pointer can ever be dereferenced.
        if tapInstalled { mixer.removeTap(onBus: 0); tapInstalled = false }
        bridge.stop()
    }
    deinit {
        // Actor-isolated stop is called explicitly from the controller.
        // The ring has independent ownership in tap and writer closures.
    }
}
