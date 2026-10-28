import AVFAudio
import AudioToolbox
import SwiftUI

/// The audio callback has no application logic: it forwards float buffer pointers
/// to the C++ core. All persistence, import and offline export work is off callback.
final class RenderBridge: @unchecked Sendable {
    private let core: OpaquePointer

    init(core: OpaquePointer) { self.core = core }

    func render(frames: AVAudioFrameCount, into list: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count == 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
            for index in 0..<buffers.count {
                if let data = buffers[index].mData {
                    memset(data, 0, Int(buffers[index].mDataByteSize))
                }
            }
            return noErr
        }
        tb_render(core, left, right, Int(frames))
        return noErr
    }

    func configure(_ session: TrackProject) {
        tb_set_bpm(core, session.bpm)
        tb_set_swing(core, Float(session.swing))
        tb_set_crossfader(core, Float(session.crossfader))
        tb_set_master_gain(core, Float(session.masterGain))
        for deck in 0..<2 {
            tb_set_deck_gain(core, Int32(deck), Float(session.deckGain[deck]))
            for voice in 0..<3 {
                tb_set_pattern_voice_mute(core, Int32(deck), Int32(voice),
                                          session.patternMute[deck][voice] ? 1 : 0)
                tb_set_pattern_voice_solo(core, Int32(deck), Int32(voice),
                                          session.patternSolo[deck][voice] ? 1 : 0)
            }
            tb_set_deck_filter(core, Int32(deck), Float(session.deckFilter[deck]))
            tb_set_deck_delay(core, Int32(deck), Float(session.deckDelay[deck]))
            for band in 0..<3 {
                tb_set_deck_eq(core, Int32(deck), Int32(band), Float(session.deckEQ[deck][band]))
            }
            tb_select_bank(core, Int32(deck), Int32(session.bank[deck]))
            for bank in 0..<4 {
                for voice in 0..<3 {
                    for step in 0..<16 {
                        tb_set_velocity_bank(core, Int32(deck), Int32(bank), Int32(voice),
                            Int32(step), Int32(session.velocity[deck][bank][voice][step]))
                    }
                }
            }
        }
    }

    func setPlaying(_ value: Bool) { tb_set_playing(core, value ? 1 : 0) }
    func setBPM(_ value: Double) { tb_set_bpm(core, value) }
    func setSwing(_ value: Float) { tb_set_swing(core, value) }
    func setCrossfader(_ value: Float) { tb_set_crossfader(core, value) }
    func setGain(_ value: Float) { tb_set_master_gain(core, value) }
    func setDeckGain(deck: Int, _ value: Float) { tb_set_deck_gain(core, Int32(deck), value) }
    func setDeckFilter(deck: Int, _ value: Float) { tb_set_deck_filter(core, Int32(deck), value) }
    func setDeckDelay(deck: Int, _ value: Float) { tb_set_deck_delay(core, Int32(deck), value) }
    func setDeckEnabled(deck: Int, _ value: Bool) { tb_set_deck_enabled(core, Int32(deck), value ? 1 : 0) }
    func setEQ(deck: Int, band: Int, db: Float) { tb_set_deck_eq(core, Int32(deck), Int32(band), db) }
    func barProgress() -> Float { tb_bar_progress(core) }
    func selectBank(deck: Int, bank: Int) { tb_select_bank(core, Int32(deck), Int32(bank)) }
    func activeBank(deck: Int) -> Int { Int(tb_active_bank(core, Int32(deck))) }
    func setVelocity(deck: Int, bank: Int, voice: Int, step: Int, velocity: Int) {
        tb_set_velocity_bank(core, Int32(deck), Int32(bank), Int32(voice), Int32(step), Int32(velocity))
    }
    func triggerPad(deck: Int, voice: Int) { tb_trigger_pad(core, Int32(deck), Int32(voice)) }
    func setPatternMute(deck: Int, voice: Int, muted: Bool) {
        tb_set_pattern_voice_mute(core, Int32(deck), Int32(voice), muted ? 1 : 0)
    }
    func setPatternSolo(deck: Int, voice: Int, solo: Bool) {
        tb_set_pattern_voice_solo(core, Int32(deck), Int32(voice), solo ? 1 : 0)
    }
    func scheduleAutoMix(targetDeck: Int, bars: Int) {
        tb_schedule_pattern_automix(core, Int32(targetDeck), Int32(bars))
    }
    func cancelAutoMix() { tb_cancel_pattern_automix(core) }
    func autoMixState() -> Int { Int(tb_automix_state(core)) }
    func effectiveCrossfader() -> Float { tb_effective_crossfader(core) }
    func reset() { tb_request_reset(core) }
    func activeStep() -> Int { Int(tb_current_step(core)) }

    deinit { tb_destroy(core) }
}

/// Cross-actor handoff owns one fully decoded bounded PCM loop. This is never
/// accessed by the real-time render callback until AVAudioPlayerNode schedules it.
private final class PreparedFileLoop: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let startFrame: Int64
    let frameCount: UInt32
    init(buffer: AVAudioPCMBuffer, startFrame: Int64, frameCount: UInt32) {
        self.buffer = buffer
        self.startFrame = startFrame
        self.frameCount = frameCount
    }
}

@MainActor
final class AudioController: ObservableObject {
    @Published private(set) var playing = false
    @Published private(set) var deckPlaying: [Bool] = [false, false]
    @Published private(set) var fileDecks: [ImportedAudio?] = [nil, nil]
    @Published private(set) var loopingDeck: [Bool] = [false, false]
    @Published private(set) var importingDeck: Int? = nil
    /// Every import is bound to a generation. A switch to a pattern deck
    /// invalidates a still-running security-scoped copy before it can commit.
    private var importGeneration: [UInt64] = [0, 0]
    private var importTask: Task<Void, Never>?
    @Published private(set) var analyzingTempo: [Bool] = [false, false]
    @Published private(set) var waveforms: [SpectralWaveform] = [.empty(), .empty()]
    private var waveformTask: Task<Void, Never>?
    private var tempoTasks: [Task<Void, Never>?] = [nil, nil]
    @Published private(set) var project = TrackProject()
    @Published private(set) var errorMessage: String?
    @Published private(set) var isExporting = false
    @Published private(set) var isRecordingLive = false
    @Published private(set) var savingLiveRecording = false
    @Published private(set) var liveRecordingResult: LiveRecordingResult?
    @Published private(set) var exportedURL: URL?
    @Published private(set) var autoMixState = 0
    @Published private(set) var timedBlendActive = false
    @Published private(set) var beatHintArmed = false
    @Published private(set) var beatHintCountdown: Double = 0
    @Published private(set) var timedBlendProgress: Double = 0
    @Published private(set) var liveCrossfader: Double = 0.5

    var bpm: Double { project.bpm }
    var swing: Double { project.swing }
    var crossfader: Double { project.crossfader }
    var gain: Double { project.masterGain }
    var fileTempoCompatibility: TempoCompatibility {
        TempoCompatibility.compare(fileDecks[0]?.tempo, fileDecks[1]?.tempo)
    }

    private let audioEngine = AVAudioEngine()
    private let filePlayers = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let fileEqualizers = [AVAudioUnitEQ(numberOfBands: 4), AVAudioUnitEQ(numberOfBands: 4)]
    private let fileDelays = [AVAudioUnitDelay(), AVAudioUnitDelay()]
    private var fileAudio: [AVAudioFile?] = [nil, nil]
    private var fileLoopBuffer: [AVAudioPCMBuffer?] = [nil, nil]
    private var fileLoopStart: [Int64] = [0, 0]
    private var fileLoopLength: [Int64] = [0, 0]
    private var fileLoopTasks: [Task<Void, Never>?] = [nil, nil]
    private var loopGeneration: [UInt64] = [0, 0]
    private var importedStore = ImportedAudioStore()
    private var playersConnected = false
    private var audioSampleRate: Double = 0
    private var source: AVAudioSourceNode?
    private var liveRecorder: LiveMixRecorder?
    private var bridge: RenderBridge?
    private var saveTask: Task<Void, Never>?
    private var autoMixTargetDeck: Int?
    private var autoMixWasActive = false
    private var timedBlendTask: Task<Void, Never>?
    private var beatHintTask: Task<Void, Never>?
    private var beatHintGeneration: UInt64 = 0
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    init() {
        #if DEBUG
        DebugUITestFixture.installIfRequested()
        #endif
        importedStore = ImportedAudioStore.load()
        for deck in 0..<2 {
            if let meta = importedStore.decks[deck],
               let path = ImportedAudioStore.fileURL(for: meta),
               let file = try? AVAudioFile(forReading: path), file.length > 0 {
                fileAudio[deck] = file
                fileDecks[deck] = meta
            }
        }
        do { project = try TrackProject.load() }
        catch { errorMessage = "Saved project could not be opened: \(error.localizedDescription)" }
        // Reconcile the restored persisted fader state BEFORE first audio start.
        liveCrossfader = project.crossfader
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleInterruption(notification) }
        }
        updateWaveforms()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleRouteChange(notification) }
        }
        for deck in 0..<2 where fileDecks[deck] != nil &&
            (fileDecks[deck]?.tempo == nil || fileDecks[deck]?.beatGrid == nil) {
            scheduleTempoAnalysis(deck)
        }
    }

    deinit {
        // Stop the mixer tap before removing the graph.
        liveRecorder?.stop()
        audioEngine.stop()
        if let source { audioEngine.detach(source) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        saveTask?.cancel()
        importTask?.cancel()
        timedBlendTask?.cancel()
        beatHintTask?.cancel()
        waveformTask?.cancel()
        for task in tempoTasks { task?.cancel() }
        for task in fileLoopTasks { task?.cancel() }
    }

    /// A user gesture starts/stops a REAL master-tap WAV capture, never an
    /// offline re-render. Xcode/device audio routing must be verified.
    func toggleLiveRecording() {
        if isRecordingLive {
            isRecordingLive = false
            savingLiveRecording = true
            liveRecorder?.stop()
            liveRecorder = nil
            return
        }
        guard !savingLiveRecording else { return }
        guard playing, audioEngine.isRunning else {
            errorMessage = "Play a deck before starting a live master recording."
            return
        }
        do {
            liveRecordingResult = nil
            let recorder = try LiveMixRecorder(mixer: audioEngine.mainMixerNode) { [weak self] result in
                guard let self else { return }
                self.savingLiveRecording = false
                switch result {
                case .success(let record):
                    self.liveRecordingResult = record
                    self.errorMessage = record.droppedFrames > 0 ?
                        "Recording has \(record.droppedFrames) dropped frames; inspect before use." : nil
                case .failure(let error):
                    self.liveRecorder?.stop()
                    self.liveRecorder = nil
                    self.isRecordingLive = false
                    self.errorMessage = "Live recording failed: \(error.localizedDescription)"
                }
            }
            liveRecorder = recorder
            isRecordingLive = true
            errorMessage = nil
        } catch {
            errorMessage = "Recording unavailable: \(error.localizedDescription)"
        }
    }

    private func prepareEngine() throws {
        if bridge != nil { return }
        let session = AVAudioSession.sharedInstance()
        // Activate ONLY after an explicit Play or Pad user gesture.
        try session.setCategory(.playback, mode: .default)
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.0053)
        try session.setActive(true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: session.sampleRate, channels: 2),
              let core = tb_create(session.sampleRate) else {
            throw NSError(domain: "TrackBuilderAudio", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to initialize stereo audio core"])
        }
        audioSampleRate = session.sampleRate
        let newBridge = RenderBridge(core: core)
        newBridge.configure(project)
        for deck in 0..<2 { newBridge.setDeckEnabled(deck: deck, deckPlaying[deck] && fileAudio[deck] == nil) }
        let node = AVAudioSourceNode(format: format) { _, _, frames, outputData in
            newBridge.render(frames: frames, into: outputData)
        }
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        if !playersConnected {
            for deck in 0..<2 {
                let player = filePlayers[deck], eq = fileEqualizers[deck], delay = fileDelays[deck]
                eq.bands[0].filterType = .lowShelf
                eq.bands[0].frequency = 180
                eq.bands[1].filterType = .parametric
                eq.bands[1].frequency = 1000
                eq.bands[1].bandwidth = 0.75
                eq.bands[2].filterType = .highShelf
                eq.bands[2].frequency = 6200
                for band in 0..<3 {
                    eq.bands[band].gain = Float(project.deckEQ[deck][band])
                    eq.bands[band].bypass = false
                }
                eq.bands[3].filterType = .lowPass
                eq.bands[3].frequency = 120 + Float(project.deckFilter[deck] * 18000)
                eq.bands[3].bypass = false
                delay.delayTime = 0.375
                delay.feedback = 28
                delay.wetDryMix = Float(project.deckDelay[deck] * 100)
                audioEngine.attach(player)
                audioEngine.attach(eq)
                audioEngine.attach(delay)
                audioEngine.connect(player, to: eq, format: nil)
                audioEngine.connect(eq, to: delay, format: nil)
                audioEngine.connect(delay, to: audioEngine.mainMixerNode, format: nil)
            }
            playersConnected = true
        }
        bridge = newBridge
        updateFileVolumes()
        source = node
    }

    /// Global transport retained for accessibility and background safety.
    func togglePlayback() {
        if playing {
            pauseAllDecks()
        } else {
            startDeck(0)
            startDeck(1)
        }
    }

    /// Independent, explicit deck transport. Synth pattern decks share the
    /// sample-clock; loaded file decks have their own native player transport.
    func toggleDeckPlayback(_ deck: Int) {
        guard (0..<2).contains(deck) else { return }
        if deckPlaying[deck] { pauseDeck(deck) } else { startDeck(deck) }
    }

    private func startDeck(_ deck: Int) {
        guard (0..<2).contains(deck) else { return }
        do {
            try prepareEngine() // Called only from explicit PLAY/PAD gesture.
            if !audioEngine.isRunning { try audioEngine.start() }
            if let file = fileAudio[deck] {
                let player = filePlayers[deck]
                // A previously paused node resumes its scheduled position.
                // Fresh file loading and CUE reschedule from the start.
                if !player.isPlaying {
                    if !fileScheduled[deck] {
                        _ = scheduleFile(deck, file: file, at: filePausedFrame[deck] < file.length ?
                            filePausedFrame[deck] : 0)
                    }
                    player.play()
                }
            } else {
                bridge?.setDeckEnabled(deck: deck, true)
            }
            deckPlaying[deck] = true
            bridge?.setPlaying(true)
            playing = true
            errorMessage = nil
            updateFileVolumes()
        } catch {
            errorMessage = "Deck \(deck == 0 ? "A" : "B"): \(error.localizedDescription)"
        }
    }

    private var fileScheduled: [Bool] = [false, false]
    private var fileGeneration: [UInt64] = [0, 0]
    private var fileStartFrame: [AVAudioFramePosition] = [0, 0]
    private var filePausedFrame: [AVAudioFramePosition] = [0, 0]

    private func currentFrame(_ deck: Int) -> AVAudioFramePosition {
        guard let file = fileAudio[deck] else { return 0 }
        if !deckPlaying[deck] { return min(file.length - 1, filePausedFrame[deck]) }
        guard let renderTime = filePlayers[deck].lastRenderTime,
              let playerTime = filePlayers[deck].playerTime(forNodeTime: renderTime) else {
            return filePausedFrame[deck]
        }
        // A node's player sampleTime counts samples rendered since start;
        // fileStartFrame is the absolute seek origin in the file.
        let base = fileStartFrame[deck]
        let elapsed = max(0, Double(playerTime.sampleTime) *
                         file.processingFormat.sampleRate / playerTime.sampleRate)
        if loopingDeck[deck] && fileLoopLength[deck] > 0 {
            let within = AVAudioFramePosition(elapsed) % fileLoopLength[deck]
            return min(file.length - 1, fileLoopStart[deck] + within)
        }
        return min(file.length - 1, base + AVAudioFramePosition(elapsed))
    }

    /// Reschedule a file from its actual PCM frame. Invocation is restricted
    /// to the controller thread; the old generation's EOF is discarded.
    @discardableResult
    private func scheduleFile(_ deck: Int, file: AVAudioFile, at frame: AVAudioFramePosition) -> Bool {
        guard file.length > 0, frame >= 0, frame < file.length else { return false }
        fileGeneration[deck] &+= 1
        let generation = fileGeneration[deck]
        loopingDeck[deck] = false
        fileLoopBuffer[deck] = nil
        fileLoopLength[deck] = 0
        fileStartFrame[deck] = frame
        filePausedFrame[deck] = frame
        // scheduleSegment uses AVAudioFrameCount (32-bit); this alpha safely
        // bounds the scheduled read instead of overflowing the parameter.
        let frames = AVAudioFrameCount(min(file.length - frame, Int64(UInt32.max)))
        filePlayers[deck].scheduleSegment(file, startingFrame: frame, frameCount: frames,
                                at: nil, completionCallbackType: .dataPlayedBack) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.fileGeneration[deck] == generation else { return }
                self.fileScheduled[deck] = false
                self.deckPlaying[deck] = false
                // File ended: next user PLAY restarts from its first frame.
                self.filePausedFrame[deck] = 0
                self.fileStartFrame[deck] = 0
                self.filePlayers[deck].stop()
                self.updatePlaybackFlag()
            }
        }
        fileScheduled[deck] = true
        return true
    }

    /// Enables a PCM-buffer loop on a single native file deck. A 4/8/16 beat
    /// excerpt is loaded on a utility worker; AVAudioPlayerNode's .loops
    /// option then repeats it in audio sample coordinates without a Swift
    /// timer or a per-repetition schedule callback. Never loads >16 seconds.
    func activateFileLoop(_ deck: Int, beats: Int) {
        guard (0..<2).contains(deck),
              let meta = fileDecks[deck], let file = fileAudio[deck],
              let grid = meta.beatGrid,
              let plan = FileLoopPlan.make(grid: grid,
                        near: Double(currentFrame(deck)) / file.processingFormat.sampleRate,
                        duration: meta.duration, beats: beats),
              let url = ImportedAudioStore.fileURL(for: meta) else {
            errorMessage = "LOOP requires an analyzed or manually corrected beat grid and enough remaining audio."
            return
        }
        guard (meta.manuallyAdjustedGrid == true || grid.confidence >= 0.60) else {
            errorMessage = "Beat grid is too uncertain for LOOP. Adjust the grid manually."
            return
        }
        // The mixer graph determines the actual AVAudioPlayerNode output rate.
        // PCM buffers must be converted to that rate; unlike file segments,
        // AVAudioPlayerNode buffer playback assumes source/output rates agree.
        do { try prepareEngine() }
        catch {
            errorMessage = "Cannot prepare file LOOP audio: \(error.localizedDescription)"
            return
        }
        let playbackRate = audioSampleRate
        loopGeneration[deck] &+= 1
        let generation = loopGeneration[deck]
        fileLoopTasks[deck]?.cancel()
        fileLoopTasks[deck] = Task { [weak self] in
            do {
                let prepared = try await BackgroundWork.run(priority: .userInitiated) {
                    let reader = try AVAudioFile(forReading: url,
                          commonFormat: .pcmFormatFloat32, interleaved: false)
                    guard let (start, count) = plan.pcmRange(
                           sampleRate: reader.processingFormat.sampleRate,
                           totalFrames: reader.length),
                          let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat,
                              frameCapacity: count) else {
                        throw NSError(domain: "FileLoop", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid loop PCM bounds"])
                    }
                    reader.framePosition = start
                    try reader.read(into: buffer, frameCount: count)
                    guard buffer.frameLength == count else {
                        throw NSError(domain: "FileLoop", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Loop audio read was incomplete"])
                    }
                    let output: AVAudioPCMBuffer
                    if abs(reader.processingFormat.sampleRate - playbackRate) < 0.5 &&
                        reader.processingFormat.channelCount == 2 {
                        output = buffer
                    } else {
                        guard let destinationFormat = AVAudioFormat(
                            standardFormatWithSampleRate: playbackRate, channels: 2),
                              let converter = AVAudioConverter(from: reader.processingFormat,
                                                               to: destinationFormat) else {
                            throw NSError(domain: "FileLoop", code: 3,
                                userInfo: [NSLocalizedDescriptionKey: "Audio resampler unavailable"])
                        }
                        let capacity = AVAudioFrameCount(ceil(
                            Double(count) * playbackRate /
                            reader.processingFormat.sampleRate) + 128)
                        guard let converted = AVAudioPCMBuffer(pcmFormat: destinationFormat,
                                                               frameCapacity: capacity) else {
                            throw NSError(domain: "FileLoop", code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "Cannot allocate converted loop"])
                        }
                        var inputPending = true
                        var conversionError: NSError?
                        let status = converter.convert(to: converted,
                            error: &conversionError) { _, inputStatus in
                            if !inputPending {
                                inputStatus.pointee = .endOfStream
                                return nil
                            }
                            inputPending = false
                            inputStatus.pointee = .haveData
                            return buffer
                        }
                        guard status != .error, converted.frameLength > 0 else {
                            throw conversionError ?? NSError(domain: "FileLoop", code: 5,
                                userInfo: [NSLocalizedDescriptionKey: "Loop sample-rate conversion failed"])
                        }
                        output = converted
                    }
                    return PreparedFileLoop(buffer: output,
                                            startFrame: start, frameCount: count)
                }
                guard let self, !Task.isCancelled,
                      self.loopGeneration[deck] == generation,
                      self.fileDecks[deck]?.fileName == meta.fileName,
                      self.fileAudio[deck] != nil else { return }
                // Persist the new region before changing the live graph.
                guard let current = self.fileDecks[deck] else { return }
                let changed = ImportedAudio(fileName: current.fileName,
                    title: current.title, duration: current.duration,
                    tempo: current.tempo, beatGrid: current.beatGrid,
                    manuallyAdjustedGrid: current.manuallyAdjustedGrid,
                    hotCues: current.hotCues, loop: plan)
                guard changed.isValid else { return }
                var next = self.importedStore
                next.decks[deck] = changed
                try next.save()
                self.importedStore = next
                self.fileDecks[deck] = changed
                self.cancelBeatHintBlend()
                self.cancelTimedBlend()
                let wasPlaying = self.deckPlaying[deck]
                self.fileGeneration[deck] &+= 1
                self.filePlayers[deck].stop()
                self.fileScheduled[deck] = true
                self.fileLoopBuffer[deck] = prepared.buffer
                self.fileLoopStart[deck] = prepared.startFrame
                self.fileLoopLength[deck] = Int64(prepared.frameCount)
                self.fileStartFrame[deck] = prepared.startFrame
                self.filePausedFrame[deck] = prepared.startFrame
                self.loopingDeck[deck] = true
                self.filePlayers[deck].scheduleBuffer(prepared.buffer, at: nil,
                                                     options: [.loops], completionHandler: nil)
                if wasPlaying { self.filePlayers[deck].play() }
                self.errorMessage = nil
            } catch {
                guard let self, self.loopGeneration[deck] == generation else { return }
                self.errorMessage = "File LOOP could not be activated: \(error.localizedDescription)"
            }
        }
    }

    /// Leave the repeating PCM excerpt at its actual in-loop file position.
    func exitFileLoop(_ deck: Int) {
        guard (0..<2).contains(deck) else { return }
        loopGeneration[deck] &+= 1
        fileLoopTasks[deck]?.cancel()
        fileLoopTasks[deck] = nil
        guard loopingDeck[deck], let file = fileAudio[deck] else { return }
        let position = currentFrame(deck)
        let wasPlaying = deckPlaying[deck]
        fileGeneration[deck] &+= 1
        filePlayers[deck].stop()
        loopingDeck[deck] = false
        fileLoopBuffer[deck] = nil
        fileLoopLength[deck] = 0
        fileScheduled[deck] = false
        _ = scheduleFile(deck, file: file, at: min(file.length - 1, position))
        if wasPlaying { filePlayers[deck].play() }
    }

    /// Audio-file seek is an actual player-node reschedule, not a UI simulation.
    /// No other deck or the pattern clock is reset.
    func seekDeck(_ deck: Int, to seconds: Double) {
        cancelBeatHintBlend()
        if (0..<2).contains(deck) { loopGeneration[deck] &+= 1; fileLoopTasks[deck]?.cancel() }
        guard (0..<2).contains(deck), let file = fileAudio[deck],
              let frame = FileDeckPerformance.seekFrame(seconds: seconds,
                sampleRate: file.processingFormat.sampleRate, length: file.length) else {
            errorMessage = "Seek position is outside the loaded track."
            return
        }
        let wasPlaying = deckPlaying[deck]
        fileGeneration[deck] &+= 1
        filePlayers[deck].stop()
        fileScheduled[deck] = false
        guard scheduleFile(deck, file: file, at: frame) else { return }
        if wasPlaying { filePlayers[deck].play() }
        errorMessage = nil
    }

    /// Set/delete/jump actual file hot cues without touching other deck.
    func storeHotCue(_ deck: Int, slot: Int) {
        guard (0..<2).contains(deck), let current = fileDecks[deck],
              let file = fileAudio[deck], file.length > 0 else { return }
        let seconds = Double(currentFrame(deck)) / file.processingFormat.sampleRate
        guard let changed = FileDeckPerformance.setCue(current, slot: slot, seconds: seconds) else { return }
        saveCueMetadata(deck: deck, current: current, changed: changed)
    }
    func clearHotCue(_ deck: Int, slot: Int) {
        guard (0..<2).contains(deck), let current = fileDecks[deck],
              let changed = FileDeckPerformance.clearCue(current, slot: slot) else { return }
        saveCueMetadata(deck: deck, current: current, changed: changed)
    }
    func jumpHotCue(_ deck: Int, slot: Int) {
        guard (0..<2).contains(deck), let current = fileDecks[deck],
              let seconds = FileDeckPerformance.cuePosition(current, slot: slot) else { return }
        seekDeck(deck, to: seconds)
    }
    private func saveCueMetadata(deck: Int, current: ImportedAudio, changed: ImportedAudio) {
        var next = importedStore
        guard next.decks[deck] == current else { return }
        next.decks[deck] = changed
        do {
            try next.save()
            importedStore = next
            fileDecks[deck] = changed
        } catch {
            errorMessage = "Could not save Hot Cues: \(error.localizedDescription)"
        }
    }

    private func scheduleFileFromStart(_ deck: Int, file: AVAudioFile) {
        _ = scheduleFile(deck, file: file, at: 0)
    }

    private func pauseDeck(_ deck: Int) {
        cancelBeatHintBlend()
        guard (0..<2).contains(deck) else { return }
        if fileAudio[deck] != nil { filePausedFrame[deck] = currentFrame(deck) }
        deckPlaying[deck] = false
        filePlayers[deck].pause()
        bridge?.setDeckEnabled(deck: deck, false)
        updatePlaybackFlag()
    }

    private func pauseAllDecks() {
        cancelBeatHintBlend()
        for deck in 0..<2 {
            if fileAudio[deck] != nil { filePausedFrame[deck] = currentFrame(deck) }
            deckPlaying[deck] = false
            filePlayers[deck].pause()
            bridge?.setDeckEnabled(deck: deck, false)
        }
        updatePlaybackFlag()
    }

    private func updatePlaybackFlag() {
        let anyPlaying = deckPlaying.contains(true)
        bridge?.setPlaying(anyPlaying)
        if !anyPlaying { audioEngine.pause() }
        playing = anyPlaying
    }

    /// CUE returns a file deck to the start while preserving the other deck.
    func cueDeck(_ deck: Int) {
        cancelBeatHintBlend()
        if (0..<2).contains(deck) { loopGeneration[deck] &+= 1; fileLoopTasks[deck]?.cancel() }
        guard (0..<2).contains(deck), let file = fileAudio[deck] else { return }
        // Pauses one deck and reschedules from its first PCM frame.
        deckPlaying[deck] = false
        fileGeneration[deck] &+= 1
        filePlayers[deck].stop()
        fileScheduled[deck] = false
        _ = scheduleFile(deck, file: file, at: 0)
        updatePlaybackFlag()
    }

    /// Called on the main/control thread, never the audio render callback.
    /// The C++ synthesized signal has its own per-deck equal-power fader;
    /// imported AVAudioPlayerNode sources use the corresponding file fader.
    private func updateFileVolumes() {
        let xf = min(1, max(0, liveCrossfader))
        for deck in 0..<2 {
            let weight = sqrt(deck == 0 ? 1 - xf : xf)
            filePlayers[deck].volume = Float(weight * project.deckGain[deck] * project.masterGain)
        }
    }

    /// Estimates BPM conservatively without enabling file SYNC. Results are
    /// persisted only if the exact source file remains in this deck.
    private func scheduleTempoAnalysis(_ deck: Int) {
        guard (0..<2).contains(deck), let imported = fileDecks[deck],
              (imported.tempo == nil || imported.beatGrid == nil),
              let url = ImportedAudioStore.fileURL(for: imported) else { return }
        tempoTasks[deck]?.cancel()
        analyzingTempo[deck] = true
        tempoTasks[deck] = Task { [weak self] in
            let analysis = try? await BackgroundWork.run(priority: .utility) {
                try AudioTempoExtractor.analyze(url)
            }
            guard !Task.isCancelled else { return }
            guard let self, let current = self.fileDecks[deck],
                  current.fileName == imported.fileName else { return }
            self.analyzingTempo[deck] = false
            guard let estimate = analysis?.tempo,
                  let updated = AnalysisMergePolicy.merge(
                    original: imported, current: current,
                    estimated: estimate, grid: analysis?.beatGrid),
                  self.importedStore.decks[deck] == current else { return }
            var next = self.importedStore
            next.decks[deck] = updated
            do {
                try next.save()
                self.importedStore = next
                self.fileDecks[deck] = updated
            } catch {
                // No promise of a cached tempo until it can be persisted.
                self.errorMessage = "Tempo estimate could not be saved."
            }
        }
    }

    /// User-confirmed tempo/phase calibration. Preserve the active deck
    /// audio and replace only metadata after the manifest is safely written.
    /// Never silently starts, seeks, warps or synchronizes a track.
    func applyManualBeatGrid(deck: Int, bpm: Double, firstBeatSeconds: Double) {
        guard (0..<2).contains(deck), let current = fileDecks[deck],
              let corrected = BeatGridEditor.corrected(current, bpm: bpm,
                                                      firstBeatSeconds: firstBeatSeconds) else {
            errorMessage = "Manual beat grid contains invalid values."
            return
        }
        var next = importedStore
        next.decks[deck] = corrected
        do {
            try next.save()
            tempoTasks[deck]?.cancel()
            analyzingTempo[deck] = false
            importedStore = next
            fileDecks[deck] = corrected
            errorMessage = nil
        } catch {
            errorMessage = "Manual beat grid could not be saved: \(error.localizedDescription)"
        }
    }

    func reportImportFailure(_ error: Error) {
        errorMessage = "Could not open Files: \(error.localizedDescription)"
    }

    func importAudioFile(_ source: URL, into deck: Int) {
        cancelBeatHintBlend()
        guard (0..<2).contains(deck), importingDeck == nil else { return }
        loopGeneration[deck] &+= 1
        fileLoopTasks[deck]?.cancel()
        importGeneration[deck] &+= 1
        let generation = importGeneration[deck]
        importingDeck = deck
        importTask = Task {
            // Reserve the owned path OUTSIDE the detached worker. If the
            // parent is cancelled after copy but before returning, cleanup
            // can still find the partially/imported file.
            let ext = source.pathExtension.lowercased()
            let safeExt = ext.range(of: "^[a-z0-9]{1,12}$", options: .regularExpression) != nil
                ? ext : "audio"
            let destination = ImportedAudioStore.folder.appendingPathComponent(
                "\(UUID().uuidString).\(safeExt)")
            var pendingCopy: URL? = destination
            do {
                // Security scope and potentially large copy happen off main.
                let imported: ImportedAudio = try await BackgroundWork.run(priority: .userInitiated) {
                    let access = source.startAccessingSecurityScopedResource()
                    defer { if access { source.stopAccessingSecurityScopedResource() } }
                    let file = try AVAudioFile(forReading: source)
                    guard file.length > 0, file.processingFormat.sampleRate > 0 else {
                        throw NSError(domain: "TrackBuilderImport", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Unsupported or empty audio file"])
                    }
                    let duration = Double(file.length) / file.processingFormat.sampleRate
                    guard duration <= 60 * 60 * 12 else {
                        throw NSError(domain: "TrackBuilderImport", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Audio file is too long"])
                    }
                    try FileManager.default.createDirectory(at: ImportedAudioStore.folder,
                                                            withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: source, to: destination)
                    return ImportedAudio(fileName: destination.lastPathComponent,
                                         title: source.deletingPathExtension().lastPathComponent,
                                         duration: duration)
                }
                try Task<Never, Never>.checkCancellation()
                guard ImportCommitPolicy.mayCommit(expectedGeneration: generation,
                      currentGeneration: self.importGeneration[deck],
                      activeImportDeck: self.importingDeck,
                      requestedDeck: deck) else { throw CancellationError() }
                guard let path = ImportedAudioStore.fileURL(for: imported) else {
                    throw NSError(domain: "TrackBuilderImport", code: 4,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid imported path"])
                }
                pendingCopy = path
                let opened = try AVAudioFile(forReading: path)
                // After any suspension, recheck the user's current source
                // choice before publishing the copy into the deck manifest.
                try Task<Never, Never>.checkCancellation()
                guard ImportCommitPolicy.mayCommit(expectedGeneration: generation,
                      currentGeneration: self.importGeneration[deck],
                      activeImportDeck: self.importingDeck,
                      requestedDeck: deck) else { throw CancellationError() }
                // The new file is fully validated before replacing old audio.
                let previous = fileDecks[deck]
                var updatedManifest = importedStore
                updatedManifest.decks[deck] = imported
                try updatedManifest.save() // Publish only after successful validation + persistence.
                importedStore = updatedManifest
                tempoTasks[deck]?.cancel()
                fileGeneration[deck] &+= 1
                filePlayers[deck].stop()
                fileScheduled[deck] = false
                fileLoopBuffer[deck] = nil
                fileLoopLength[deck] = 0
                loopingDeck[deck] = false
                fileAudio[deck] = opened
                fileStartFrame[deck] = 0
                filePausedFrame[deck] = 0
                fileDecks[deck] = imported
                analyzingTempo[deck] = false
                deckPlaying[deck] = false
                bridge?.setDeckEnabled(deck: deck, false)
                if let old = previous, let oldURL = ImportedAudioStore.fileURL(for: old) {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                updatePlaybackFlag()
                updateWaveforms()
                scheduleTempoAnalysis(deck)
                pendingCopy = nil
                errorMessage = nil
            } catch {
                if let pendingCopy { try? FileManager.default.removeItem(at: pendingCopy) }
                if self.importGeneration[deck] == generation && !(error is CancellationError) {
                    errorMessage = "Import failed: \(error.localizedDescription). Previous deck preserved."
                }
            }
            if self.importGeneration[deck] == generation {
                importingDeck = nil
                importTask = nil
            }
        }
    }

    /// Explicit deck switch is transactional: persist removal of the old
    /// reference BEFORE changing live player state or deleting an owned file.
    /// Persist manifest change before modifying the live graph. Stop the
    /// old player before deleting its app-owned audio file.
    func usePatternDeck(_ deck: Int) {
        cancelBeatHintBlend()
        guard (0..<2).contains(deck) else { return }
        // A user switch beats an unfinished import. Its detached file copy
        // may finish later, but it can no longer install audio/metadata.
        importGeneration[deck] &+= 1
        if importingDeck == deck {
            importTask?.cancel()
            importTask = nil
            importingDeck = nil
        }
        loopGeneration[deck] &+= 1
        fileLoopTasks[deck]?.cancel()
        let previous = importedStore.decks[deck]
        if previous != nil {
            var next = importedStore
            next.decks[deck] = nil
            do {
                try next.save()
                importedStore = next
            } catch {
                errorMessage = "Could not clear deck manifest: \(error.localizedDescription)"
                return
            }
        }
        pauseDeck(deck)
        tempoTasks[deck]?.cancel()
        analyzingTempo[deck] = false
        fileGeneration[deck] &+= 1
        filePlayers[deck].stop()
        fileScheduled[deck] = false
        fileLoopBuffer[deck] = nil
        fileLoopLength[deck] = 0
        loopingDeck[deck] = false
        fileAudio[deck] = nil
        fileStartFrame[deck] = 0
        filePausedFrame[deck] = 0
        fileDecks[deck] = nil
        if let previous, let path = ImportedAudioStore.fileURL(for: previous) {
            try? FileManager.default.removeItem(at: path)
        }
        updateWaveforms()
    }

    func setBPM(_ value: Double) {
        project.bpm = min(200, max(60, value))
        bridge?.setBPM(project.bpm)
        updateWaveforms()
        scheduleSave()
    }

    func setSwing(_ value: Double) {
        project.swing = min(0.75, max(0, value))
        bridge?.setSwing(Float(project.swing))
        updateWaveforms()
        scheduleSave()
    }

    func setCrossfader(_ value: Double) {
        cancelBeatHintBlend()
        // Touching the physical crossfader is ALWAYS immediate manual takeover.
        timedBlendTask?.cancel()
        timedBlendTask = nil
        timedBlendActive = false
        timedBlendProgress = 0
        autoMixTargetDeck = nil
        autoMixWasActive = false
        autoMixState = 0
        project.crossfader = min(1, max(0, value))
        bridge?.setCrossfader(Float(project.crossfader))
        liveCrossfader = project.crossfader
        updateFileVolumes()
        scheduleSave()
    }

    func setGain(_ value: Double) {
        project.masterGain = min(1, max(0, value))
        bridge?.setGain(Float(project.masterGain))
        updateFileVolumes()
        scheduleSave()
    }

    func setDeckGain(deck: Int, _ value: Double) {
        guard (0..<2).contains(deck) else { return }
        project.deckGain[deck] = min(1, max(0, value))
        bridge?.setDeckGain(deck: deck, Float(project.deckGain[deck]))
        updateFileVolumes()
        scheduleSave()
    }

    func setDeckDelay(deck: Int, value: Double) {
        guard (0..<2).contains(deck), value.isFinite else { return }
        project.deckDelay[deck] = min(0.5, max(0, value))
        bridge?.setDeckDelay(deck: deck, Float(project.deckDelay[deck]))
        fileDelays[deck].wetDryMix = Float(project.deckDelay[deck] * 100)
        scheduleSave()
    }

    func setDeckEQ(deck: Int, band: Int, value: Double) {
        guard (0..<2).contains(deck), (0..<3).contains(band), value.isFinite else { return }
        let db = min(12, max(-12, value))
        project.deckEQ[deck][band] = db
        bridge?.setEQ(deck: deck, band: band, db: Float(db))
        fileEqualizers[deck].bands[band].gain = Float(db)
        scheduleSave()
    }

    func barProgress() -> Double { Double(bridge?.barProgress() ?? 0) }

    func deckProgress(_ deck: Int) -> Double {
        guard (0..<2).contains(deck) else { return 0 }
        guard let meta = fileDecks[deck], let file = fileAudio[deck],
              meta.duration > 0, file.length > 0 else { return barProgress() }
        return min(1, max(0, Double(currentFrame(deck)) / Double(file.length)))
    }


    func setDeckFilter(deck: Int, _ value: Double) {
        guard (0..<2).contains(deck) else { return }
        project.deckFilter[deck] = min(1, max(0, value))
        bridge?.setDeckFilter(deck: deck, Float(project.deckFilter[deck]))
        fileEqualizers[deck].bands[3].frequency = 120 + Float(project.deckFilter[deck] * 18000)
        scheduleSave()
    }

    func selectBank(deck: Int, bank: Int) {
        guard (0..<2).contains(deck), (0..<4).contains(bank) else { return }
        project.bank[deck] = bank
        bridge?.selectBank(deck: deck, bank: bank)
        updateWaveforms()
        scheduleSave()
    }

    func activeBank(deck: Int) -> Int {
        bridge?.activeBank(deck: deck) ?? project.bank[deck]
    }

    func stepVelocity(deck: Int, bank: Int, voice: Int, step: Int) -> Int {
        project.velocity[deck][bank][voice][step]
    }

    func toggleStep(deck: Int, bank: Int, voice: Int, step: Int) {
        guard (0..<2).contains(deck), (0..<4).contains(bank),
              (0..<3).contains(voice), (0..<16).contains(step) else { return }
        let before = stepVelocity(deck: deck, bank: bank, voice: voice, step: step)
        setVelocity(deck: deck, bank: bank, voice: voice, step: step,
                    value: before == 0 ? 110 : 0)
    }

    func setVelocity(deck: Int, bank: Int, voice: Int, step: Int, value: Int) {
        guard (0..<2).contains(deck), (0..<4).contains(bank),
              (0..<3).contains(voice), (0..<16).contains(step) else { return }
        let newVelocity = min(127, max(0, value))
        project.velocity[deck][bank][voice][step] = newVelocity
        bridge?.setVelocity(deck: deck, bank: bank, voice: voice, step: step, velocity: newVelocity)
        updateWaveforms()
        scheduleSave()
    }

    /// Real synthesized voice mute/solo. Does not pretend to remove vocals
    /// or instruments from imported songs, which require source separation.
    func togglePatternMute(deck: Int, voice: Int) {
        guard (0..<2).contains(deck), (0..<3).contains(voice) else { return }
        let next = !project.patternMute[deck][voice]
        project.patternMute[deck][voice] = next
        bridge?.setPatternMute(deck: deck, voice: voice, muted: next)
        updateWaveforms()
        scheduleSave()
    }
    func togglePatternSolo(deck: Int, voice: Int) {
        guard (0..<2).contains(deck), (0..<3).contains(voice) else { return }
        let next = !project.patternSolo[deck][voice]
        project.patternSolo[deck][voice] = next
        bridge?.setPatternSolo(deck: deck, voice: voice, solo: next)
        updateWaveforms()
        scheduleSave()
    }

    func triggerPad(deck: Int, voice: Int) {
        guard (0..<2).contains(deck), (0..<3).contains(voice) else { return }
        guard fileAudio[deck] == nil else {
            errorMessage = "Pads control original synth sounds, not imported tracks."
            return
        }
        if !deckPlaying[deck] { startDeck(deck) }
        bridge?.triggerPad(deck: deck, voice: voice)
    }

    func activeStep() -> Int { bridge?.activeStep() ?? 0 }

    /// BAR-quantized equal-power crossfade for *generated patterns only*.
    /// File-track beatgrid analysis is a separate, unimplemented M2 feature.
    func schedulePatternAutoMix(targetDeck: Int) {
        guard (0..<2).contains(targetDeck) else { return }
        guard fileAudio.allSatisfy({ $0 == nil }) else {
            errorMessage = "Pattern AutoMix is only available on synthesized decks. Full track AutoMix is not implemented."
            return
        }
        // Both original pattern decks must run, or fade could go to silence.
        if !deckPlaying[0] { startDeck(0) }
        if !deckPlaying[1] { startDeck(1) }
        guard deckPlaying[0] && deckPlaying[1] else { return }
        autoMixTargetDeck = targetDeck
        autoMixWasActive = false
        bridge?.scheduleAutoMix(targetDeck: targetDeck, bars: 2)
        autoMixState = 1
    }

    /// Arms a beat-HINT (not phrase) transition. Source A/B keeps playing.
    /// The target file is cued to its estimated first beat; its player starts
    /// when the source enters the next four-beat grouping. The scheduler runs
    /// on the main/control actor and may have device-dependent jitter.
    func beginBeatHintBlend(targetDeck: Int, beats: Int = 8) {
        cancelBeatHintBlend()
        guard (0..<2).contains(targetDeck),
              let source = fileAudio[1-targetDeck],
              fileAudio[targetDeck] != nil,
              deckPlaying[1-targetDeck], !deckPlaying[targetDeck],
              let origin = fileDecks[1-targetDeck],
              let destination = fileDecks[targetDeck],
              let sourceGrid = origin.beatGrid,
              let targetGrid = destination.beatGrid else {
            errorMessage = "Beat-hint blend requires playing source and a cued, stopped target file with grids."
            return
        }
        // A machine-estimated phase is NOT a confirmed downbeat. Require
        // comparatively strong evidence or a user-reviewed manual grid.
        guard (origin.manuallyAdjustedGrid == true || sourceGrid.confidence >= 0.65),
              (destination.manuallyAdjustedGrid == true || targetGrid.confidence >= 0.65) else {
            errorMessage = "Beat grids are uncertain. Correct both grids manually or use timed blend."
            return
        }
        let sourceSeconds = Double(currentFrame(1-targetDeck)) /
            source.processingFormat.sampleRate
        guard let plan = BeatHintTransition.make(source: sourceGrid, target: targetGrid,
                  sourcePosition: sourceSeconds, sourceDuration: origin.duration,
                  targetDuration: destination.duration, beats: beats) else {
            errorMessage = "No safe near-tempo beat-hint start remains. Use a manual/timed blend."
            return
        }
        // A positive target start position and a live target seek are real
        // player-node operations, not waveform-only UI animation.
        seekDeck(targetDeck, to: plan.targetCueSeconds)
        guard errorMessage == nil else { return }
        let sourceName = origin.fileName
        let targetName = destination.fileName
        beatHintGeneration &+= 1
        let generation = beatHintGeneration
        beatHintArmed = true
        beatHintCountdown = plan.leadSeconds
        beatHintTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.beatHintGeneration == generation,
                      self.deckPlaying[1-targetDeck],
                      self.fileDecks[1-targetDeck]?.fileName == sourceName,
                      self.fileDecks[targetDeck]?.fileName == targetName,
                      let playingFile = self.fileAudio[1-targetDeck] else {
                    self?.cancelBeatHintBlend()
                    return
                }
                let now = Double(self.currentFrame(1-targetDeck)) /
                    playingFile.processingFormat.sampleRate
                self.beatHintCountdown = max(0, plan.sourceCueSeconds-now)
                if now >= plan.sourceCueSeconds - 0.018 {
                    self.beatHintArmed = false
                    self.beatHintCountdown = 0
                    self.beatHintTask = nil
                    self.startFileFade(targetDeck: targetDeck, seconds: plan.blendSeconds)
                    return
                }
                // Never block the audio render thread; the start tolerance
                // is approximate and must be measured on physical devices.
                do { try await Task.sleep(nanoseconds: 8_000_000) }
                catch { return }
            }
        }
        errorMessage = nil
    }

    func cancelBeatHintBlend() {
        beatHintGeneration &+= 1
        beatHintTask?.cancel()
        beatHintTask = nil
        beatHintArmed = false
        beatHintCountdown = 0
    }

    /// Approximate audio-file blend without lying about phrase or tempo sync.
    /// Files play through independent native player nodes; the mixer fader is
    /// driven on the control thread. First beat and tempo are not changed.
    func beginTimedFileBlend(targetDeck: Int, bars: Int = 2) {
        cancelBeatHintBlend()
        guard (0..<2).contains(targetDeck),
              fileAudio[0] != nil, fileAudio[1] != nil else {
            errorMessage = "Timed file blend requires two imported audio files."
            return
        }
        let sourceBPM = fileDecks[1 - targetDeck]?.tempo?.bpm ?? project.bpm
        guard let seconds = TimedBlendPlan.approximateSeconds(bpm: sourceBPM, bars: bars) else {
            errorMessage = "Invalid file blend duration."
            return
        }
        startFileFade(targetDeck: targetDeck, seconds: seconds)
    }

    // Control-thread only; file players are NOT pitch/phase locked.
    private func startFileFade(targetDeck: Int, seconds: Double) {
        guard let plan = TimedBlendPlan(start: liveCrossfader,
                    target: Double(targetDeck), seconds: seconds) else {
            errorMessage = "Invalid file blend duration or fader position."
            return
        }
        if !deckPlaying[0] { startDeck(0) }
        if !deckPlaying[1] { startDeck(1) }
        guard deckPlaying[0], deckPlaying[1] else { return }
        cancelAutoMix() // clear pattern-only scheduler
        timedBlendTask?.cancel()
        timedBlendActive = true
        timedBlendProgress = 0
        let startTime = ProcessInfo.processInfo.systemUptime
        timedBlendTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                let value = plan.crossfader(at: elapsed)
                self.liveCrossfader = value
                self.bridge?.setCrossfader(Float(value))
                self.updateFileVolumes()
                self.timedBlendProgress = plan.fraction(at: elapsed)
                if elapsed >= plan.seconds { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            self.project.crossfader = plan.targetPosition
            self.bridge?.setCrossfader(Float(plan.targetPosition))
            self.liveCrossfader = plan.targetPosition
            self.timedBlendActive = false
            self.timedBlendTask = nil
            self.updateFileVolumes()
            self.scheduleSave()
        }
        errorMessage = nil
    }

    func cancelTimedBlend() {
        timedBlendTask?.cancel()
        timedBlendTask = nil
        timedBlendActive = false
        timedBlendProgress = 0
        project.crossfader = liveCrossfader
        bridge?.setCrossfader(Float(liveCrossfader))
        scheduleSave()
    }

    func cancelAutoMix() {
        guard let bridge else { return }
        bridge.cancelAutoMix()
        project.crossfader = Double(bridge.effectiveCrossfader())
        liveCrossfader = project.crossfader
        autoMixTargetDeck = nil
        autoMixWasActive = false
        autoMixState = 0
        scheduleSave()
    }

    func refreshRealtimeStatus() {
        guard let bridge else { return }
        let phase = bridge.autoMixState()
        if !timedBlendActive {
            liveCrossfader = Double(bridge.effectiveCrossfader())
            updateFileVolumes()
        }
        if autoMixTargetDeck != nil && phase != 0 { autoMixWasActive = true }
        if phase == 0 && autoMixWasActive, let target = autoMixTargetDeck {
            project.crossfader = Double(target)
            autoMixTargetDeck = nil
            autoMixWasActive = false
            scheduleSave()
        }
        if autoMixState != phase { autoMixState = phase }
    }

    func resetTransport() {
        cancelBeatHintBlend()
        cancelTimedBlend()
        bridge?.reset()
        for deck in 0..<2 { if fileAudio[deck] != nil { cueDeck(deck) } }
        autoMixTargetDeck = nil
        autoMixWasActive = false
        autoMixState = 0
    }

    func exportPatternMix() {
        guard !isExporting else { return }
        let snapshot = project
        exportedURL = nil
        isExporting = true
        Task {
            do {
                let output = try await BackgroundWork.run(priority: .utility) {
                    try OfflineExporter.renderPatternMix(snapshot)
                }
                exportedURL = output
                errorMessage = nil
            } catch {
                errorMessage = "WAV export failed: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }

    /// Debounced background analysis. C++ DSP rendering is fully isolated from
    /// the live engine; file analysis reads an app-owned copy from disk.
    private func updateWaveforms() {
        waveformTask?.cancel()
        let snapshot = project
        let paths: [URL?] = (0..<2).map { deck in
            fileDecks[deck].flatMap { ImportedAudioStore.fileURL(for: $0) }
        }
        waveformTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            let result: [SpectralWaveform]?
            do {
                result = try await BackgroundWork.run(priority: .utility) {
                    (0..<2).map { deck in
                        if Task<Never, Never>.isCancelled { return .empty() }
                        if let url = paths[deck] {
                            return (try? WaveformRenderer.audioFile(url)) ?? .empty()
                        }
                        return WaveformRenderer.pattern(snapshot, deck: deck)
                    }
                }
            } catch { return }
            guard !Task.isCancelled, let result else { return }
            waveforms = result
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do { try project.save() }
        catch { errorMessage = "Project autosave failed: \(error.localizedDescription)" }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = project
        saveTask = Task {
            do { try await Task.sleep(nanoseconds: 450_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            do { try snapshot.save() }
            catch { errorMessage = "Project autosave failed: \(error.localizedDescription)" }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            cancelBeatHintBlend()
            cancelTimedBlend()
            if isRecordingLive { toggleLiveRecording() }
            // Snapshot the real file positions BEFORE pausing the nodes;
            // AVAudioPlayerNode's lastRenderTime may become invalid after an
            // AVAudioSession interruption. Resume must not jump backward.
            pauseAllDecks()
            bridge?.cancelAutoMix()
            autoMixTargetDeck = nil
            autoMixWasActive = false
            autoMixState = 0
            audioEngine.pause()
            errorMessage = "Audio interrupted. Tap PLAY to resume when ready."
            saveNow()
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        cancelBeatHintBlend()
        cancelTimedBlend()
        // A headphones/Bluetooth disconnect may keep the SAME 48k sample
        // rate. Pausing solely on a sample-rate change can unexpectedly blast
        // the master bus through the phone speaker.
        let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = raw.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
        let change: AudioRoutePolicy.Change
        switch reason {
        case .oldDeviceUnavailable: change = .outputDisconnected
        case .noSuitableRouteForCategory: change = .routeUnavailable
        case .newDeviceAvailable: change = .outputConnected
        default: change = .configurationChanged
        }
        let rate = AVAudioSession.sharedInstance().sampleRate
        let action = AudioRoutePolicy.decision(change: change, wasPlaying: playing,
            previousRate: audioSampleRate, currentRate: rate)
        if action.pausePlayback {
            // Playback halts even when the replacement speaker uses the SAME
            // sample rate. Capture positions before the nodes are suspended.
            pauseAllDecks()
            if isRecordingLive { toggleLiveRecording() }
            errorMessage = "Audio output disconnected. Playback paused to protect your mix. Tap PLAY when ready."
        }
        guard bridge != nil else { return }
        guard action.rebuildEngine else { return }
        // Recreate the core at the new hardware rate on the NEXT user gesture.
        if isRecordingLive { toggleLiveRecording() }
        if playing { pauseAllDecks() }
        bridge?.setPlaying(false)
        for deck in 0..<2 {
            loopGeneration[deck] &+= 1
            fileLoopTasks[deck]?.cancel()
            fileLoopTasks[deck] = nil
            fileGeneration[deck] &+= 1
            filePlayers[deck].stop()
            fileScheduled[deck] = false
            loopingDeck[deck] = false
            fileLoopBuffer[deck] = nil
            fileLoopLength[deck] = 0
            deckPlaying[deck] = false
        }
        audioEngine.stop()
        if let source { audioEngine.detach(source) }
        source = nil
        bridge = nil
        playing = false
        let displayRate = rate.isFinite && rate >= 8_000 ? "\(Int(rate)) Hz" : "unknown output rate"
        errorMessage = "Audio route changed; tap PLAY to reinitialize for \(displayRate)."
    }
}
