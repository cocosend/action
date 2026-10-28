# DJ TrackBuilder MixAuto Pro — native audio architecture (0.5.0)

## Separate product boundary

Isolated native codebase, intended distinct `com.artss.trackbuilder.mixautopro` iOS bundle ID, independent Documents storage (`TrackBuilderMixAutoPro.project.json` and `MixAutoPro-Exports`). No shared repository, domain, backend, session storage or app code with Stripewolf Wave, ARTSS DJ Creator or ARTSS DJ NOVA.

## Audio engine

The graph remains: `SwiftUI` → `@MainActor AudioController` (user interactions) → `AVAudioSession` activated upon first user PLAY/Pad → `AVAudioSourceNode` → `TrackAudioCore.cpp` (C++ realtime synthesis) → `AVAudioEngine.mainMixerNode` → hardware output.

C++ engine creation/destruction are **control-thread operations**, only safe when AVAudioEngine callbacks are stopped. Render callback reads atomic input controls and owns all voice state. No dynamic allocation, locks, I/O, sample decoding, OS dispatch or network requests inside C++ `tb_render`. Swift callback only forwards two noninterleaved float buffers to C++; unexpected layouts are silenced to avoid pointer misuse.

The session requests 48 kHz and an ~5.3 ms buffer. The sample rate is taken from the *negotiated* hardware session rate. Actual latency, I/O buffer size, device interruptions, route changes and underruns must be measured on real iOS devices, not inferred.

## Sequencer and per-deck DSP

- 2 decks, each with 4 complete banks, 16 16th-note steps, 3 synth instruments per step, and velocities 0–127 in atomic U8 storage.
- Requested bank changes are activated **on the next step 0/downbeat**; initial selection activates immediately on first bar.
- Swing stretches even steps and compresses odd steps by complementary amounts, preserving each two-step duration.
- Each deck has independently smoothed volume and a one-pole low-pass filter. Stereo output uses equal-power deck crossfade with modest complementary stereo width. The master is a smoothly controlled gain followed by a bounded soft curve.
- Pads set an atomic bitmask consumed on next callback; pad triggering requires active transport, and might coincide with a pattern trigger at downbeats.
- C API is built for cross-language use and tested independently from UI.

## Experimental Pattern AutoMix

`tb_schedule_pattern_automix(engine, targetDeck, bars)` carries one atomic command into the callback. It waits for the next 16-step bar downbeat and then follows a smoothstep crossfade curve spread across 1–8 actual sequencer bars. Manual crossfader control cancels the transition at the next callback boundary. `tb_cancel_pattern_automix` holds the current audible crossfader position instead of snapping back.

This algorithm is **not beatgrid-aware AutoMix for imported files**. It works only on the project's generated pattern decks, both of which already use the same sequencer clock. Full track analysis, phrase detection and compatibility selection belong to the later M2 milestone.

## Data, export, app lifecycle

`TrackProject` is versioned Codable data and validates tempo, swing, gain, bank selections, array shape and velocities before writing. The app reads an existing local JSON project on launch; malformed projects are rejected with an error instead of partially reading inconsistent banks. UI changes autosave with a debounce; app backgrounding triggers an immediate save. No cloud service, tokens, backend requests or import of private libraries.

`OfflineExporter` builds a separate C++ synthesis engine in a background task, configures current bank/velocity/mix state and renders 16 seconds to `AVAudioFile` 16-bit PCM stereo WAV. This is **a fresh offline pattern render**, not a capture of the live hardware output, effects from other apps, microphone, or user-file playback.

## Historical M1 gap list (superseded by 0.5.0)

> This list records the original M1 state, **not current 0.5.0 status**. For current capabilities and blockers see [0.5.0 engineering](ENGINEERING-CHECKPOINT-0.5.0.md).


- Current platform container is Linux; real Xcode compilation, simulator launch, code signing and physical iPhone audio tests remain unverified. The included CI workflow is configured but not run because a separate GitHub repository has not yet been provisioned.
- User-track deck import, sample browsing, cue/hot cues, scratching, automatic BPM/beatgrid, MIDI and phase-aware multi-track AutoMix remain unimplemented.
- Real-time master recording and export of independent audio stems are unimplemented.
- Session store is local to one app installation, and audio files are not loaded; there is no sync account.
- Physical iOS tests must validate audio buffer behavior, AVAudioFile conversion to WAV, interruptions, headphones/Bluetooth, background playback, CPU, battery and memory use before release.

## 0.3.0 incremental implementation — independent file audio paths

The two pattern voices remain in `TrackAudioCore.cpp`. `tb_set_deck_enabled` gates one pattern deck without silencing its partner. Each deck can now also use a copied audio file via a separate `AVAudioPlayerNode → AVAudioUnitEQ → AVAudioEngine.mainMixerNode`. A deck whose file is present gates only its own pattern synth voice; files are streamed from app-owned storage, not decoded into a single giant in-memory `AudioBuffer`. Their AVAudioPlayerNode volumes follow the same equal-power crossfader and deck gain/master settings; imported-file EQ is `AVAudioUnitEQ` and the pattern EQ is three C++ real-time biquads. A hardware-device test is still necessary to validate exact route behavior and smoothness.

The `ImportedAudioStore` manifest persists only app-owned, validated basename strings (two decks). New Files imports are validated and copied off the main thread. The old deck file remains intact until validation and persistence have succeeded. Automatic track keys, BPM and beatgrid remain unavailable; file SYNC controls are disabled instead of pretending to work. Pattern AutoMix is deliberately prohibited when either file deck is loaded.

`WaveformRenderer` reads the copied file or independently renders the current four-bar pattern in a detached task and measures peak samples in 180 bins. Analysis is never performed in the real-time audio callback. The SwiftUI `Canvas` displays those real peak envelopes using the approved visual's multicolor aesthetic, but colors are **not claims of FFT/stem separation**. UI samples `tb_bar_progress` or the file player position for scroll offsets. Real cue markers, phrase detection and vinyl/jog are future gates.

## 0.3.1 background imported-file BPM estimator

After a successful persisted import, a background `AudioTempoExtractor` uses AVAudioFile to decode a bounded 180 s excerpt into 10 ms stereo RMS blocks. Pure Foundation `TempoAnalyzer` detects positive onset energy, normalizes cross-correlation across lags, checks half-time aliases and local tempo stability, and returns either a conservative heuristic BPM estimate or nil. This analysis never runs on the audio callback. No beat phase, key, harmonic compatibility, phrase map or time-stretch is calculated. The UI explicitly distinguishes unknown / analyzing / estimated BPM. Only cached high-confidence values are displayed. The import manifest stores the optional estimated BPM and remains backwards compatible. A deck-file identity check prevents a completed stale analysis from updating an already changed deck.

## 0.3.2 offline beat-phase hint (not SYNC)

`AudioTempoExtractor.analyze` reuses the PCM energy excerpt to estimate an *optional* first-beat offset/period via `BeatGridAnalyzer`. Pure Swift Foundation code runs only on a utility worker and never on the audio callback. It refines the lag-quantized initial BPM by ±3% and scores circular transient phase concentration. Tests demonstrate phase extraction for deterministic synthetic rhythms; a 96 BPM groove with fast offbeat hats shows the common 192 BPM octave ambiguity, so no automatic cue, SYNC or time-stretch may consume this hint without explicit further validation.

`ImportedAudio.beatGrid` is optional, persisted only when in-range and compatible with the stored `TempoEstimate`. Old manifest records without this property remain valid. The native waveform displays `BEAT GRID · APPROX` and actual evenly spaced estimated beat positions when an accepted hint exists, or `GRID UNAVAILABLE` with no pretend lines. This is neither a downbeat/phrase map nor a guarantee of stable phase through the track.

## 0.3.3 manual timing metadata editor

The WAVE page offers an explicit GRID menu for file decks. Its sheet adjusts BPM and first-beat offset, saved through `BeatGridEditor` pure Foundation validation plus transactional `ImportedAudioStore.save`. It never modifies player speed/position, so it does not misrepresent implementing beat syncing. A manually edited grid uses heuristic confidence 0 and an optional `manuallyAdjustedGrid` manifest marker; `AudioController.scheduleTempoAnalysis` now checks the full original metadata identity before committing results, preventing stale analyses from reverting a user's correction.

## 0.4–0.5 native source architecture addendum

- **File graph:** independent native `AVAudioPlayerNode` + `AVAudioUnitEQ` + `AVAudioUnitDelay` per deck. File transport, seek, up to eight Hot Cues each, and mixer volumes are controlled by the `AudioController` (control actor), not an audio thread.
- **Master recording:** native main mixer tap sends PCM through preallocated C++ SPSC capture ring to an off-thread WAV writer. Actual iPhone device behavior and recording quality remain unverified; see `LiveMixRecorder.swift`.
- **Pattern STEMS only:** original Kick/Hat/Bass voices are muted/soloed through atomic flags and smoothed in `TrackAudioCore.cpp`; the imported file itself cannot be separated into vocal/music stems. UI always distinguishes the cases.
- **Waveform spectrum:** `SpectralEnvelope.cpp` computes five first-order crossover energies from **independent stereo channels**, preventing anti-phase cancellation, and peak amplitude per bin. This is neither FFT spectral science nor source separation. `WaveformRenderer.swift` feeds C++ background analysis from actual PCM.
- **Beat-hint file mix:** `BeatHintTransition.swift` is a conservative readiness/geometry plan from analyzed or manually entered beat offsets. AudioControl uses off-callback scheduling to start an unwarped crossfade; there is no phase locking, time-stretch or musical phrase guarantee.
- **File looping:** `FileLoopPlan.swift` calculates source beat intervals of 4/8/16 pulses and valid PCM frame bounds. AVAudioFile reads a bounded loop offline; AVAudioConverter normalizes to native output rate, then `AVAudioPlayerNode.scheduleBuffer` with `.loops` is scheduled on a single deck. Device audio should be checked for click-free boundaries and exact sample alignment before claiming it production ready.
- **Safety:** C++ controls and all real-time audio rendering avoid allocations and blocking calls; background waveform/tempo/file decode have limited memory. Solo/mute/project/loop data is persisted as version-compatible JSON.

**Mandatory tests before any iPhone semi-release:** Apple SDK/Xcode build (missing here), isolated native GitHub repo, simulator UI navigation, physical iPhone A/B imported files, looping, tempo/EQ/FX audio, live WAV capture, route interruptions, tapping and screenshot comparison exclusively with the original first Canva.
