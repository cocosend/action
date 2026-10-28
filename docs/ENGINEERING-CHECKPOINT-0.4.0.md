# DJ TrackBuilder MixAuto Pro — Engineering checkpoint 0.4.0

Date: 2026-10-28. This is a SOURCE checkpoint, **not** a signed iOS IPA, a TestFlight build, or a verified on-device semi-release.

## Canonical visual source

**Only the original Canva presentation approved by the user** is the visual authority: https://www.canva.com/d/UoJgnHMYH-EJu2u (9 slides). Reject the later Canva visual reinterpretation. The code increment retains the existing graphite dual-waveform cockpit, not a new UI direction. No Canva source was modified here.

## Completed changes since 0.3.3 in the single engineering pass

| Checkpoint | Working source change | Evidence / limit |
|---|---|---|
| 0.3.4 | ImportedAudio persisted 8 file Hot Cue positions; validation and legacy-migration code | Swift value model test PASS; actual cue set/jump on device needs Xcode QA |
| 0.3.5 | Frame-specific AVAudioPlayerNode segment seek, pause/resume origin, replay from zero after EOF, first-frame CUE; no other deck reset | Pure Swift seek-frame math tests PASS; native AVAudioPlayerNode schedule/route QA pending |
| 0.3.6 | Cues on original WAVE UI, two banks 1–4 and 5–8, visible cue positions on PCM waveform | Swift syntax parser PASS; device hit-area and screenshots pending |
| 0.3.7 | Real live master tap to bounded C++ SPSC ring; off-audio-thread Float32 → PCM16 WAV writer | Concurrent ring ordering and overflow tests PASS; output WAV from actual iOS mixer NOT verified |
| 0.3.8 | Approximate control-thread timed file crossfade (not phase/tempo sync) and immediate manual takeover | Pure Swift monotone smoothstep curve tests PASS; actual music flow unverified |
| 0.3.9 | Native file deck and C++ synthesized pattern echo: 375ms delay, bounded feedback, per-deck wet controls, offline export retention | C++ audible-response/finite/sample-rate/concurrency tests PASS; iOS AVAudioUnitDelay not device tested |
| 0.4.0 | Correct persistent fader restore; transactional pattern fallback; safer end-of-file restart; prevent pads starting both decks; require both decks for pattern AutoMix; route/interruption capture cleanup | Regression and source syntax tests PASS; Apple runtime not yet verified |
| 0.4.0b | Stale analysis completes after Hot Cue edit: merge keeps the new cue while rejecting manual-grid overrides and replaced tracks | New Swift analysis-merge regression PASS |
| 0.4.0c | Tempo compatibility warnings distinguish close, unknown, octave (96/192) and mismatched BPM; never present timed file blend as true SYNC | Pure Foundation tests PASS, UI label syntax parsed |
| QA | Repeatable Linux release+ASan/UBSan C++ and Swift model pipeline; sample WAV export and level checks | **No Mac / Apple SDK used**; output proves only generated synth DSP |

## Audio graph / safety

- **Synth**: SwiftUI control → AVAudioSourceNode callback → C++17 DSP; per-deck EQ+filter+delay, gain, deck enable, crossfader, master.
- **Imported file**: AVAudioPlayerNode → AVAudioUnitEQ → AVAudioUnitDelay → AVAudioEngine.mainMixerNode. Playback, seeks and cues are native AVFAudio calls, but hardware results are unverified.
- **Record**: AVAudioEngine.mainMixerNode tap → C++ SPSC preallocated stereo ring, nonblocking producer, writer runs on a utility DispatchQueue, writes PCM16 WAV, detects dropped frames. No disk I/O or audio decoding inside the tap.
- **Offline export** remains independent and generates original patterns; do not confuse it with master tap recording.
- File imports are app-owned copies from Files; per-deck changes are persisted in a validated manifest; stale tempo analysis cannot silently overwrite manual metadata.
- Tempo/beatgrid is an approximate offline hint; no pitch-preserving sync or downbeat/phrase matching has been implemented. File crossfade operates at a computed **duration only**, not musical alignment.

## Verification summary (repeatable)

Run `scripts/verify_linux.sh`. It builds and tests core in CMake release, exercises sanitizer build, runs portable Swift model tests including file metadata, tempo, beatgrid and mix curves, parses all Swift source for syntax, renders a real **16s, 48kHz, 16-bit stereo WAV**, and validates actual PCM RMS and peak. The generated `DJ-TrackBuilder-MixAuto-Pro-0.4-FX-Demo.wav` renders two original pattern decks with true C++ echo on deck B, and has nonzero sound in all 4-second segments.

## Crucial gates that remain blocked

1. Independent GitHub repository does not exist. The linked GitHub connector has no create-repository action and remote macOS device is not connected; do **not** write the separate app into Stripewolf Wave or DJ Creator repos.
2. `xcodegen generate`, `xcodebuild` simulator compile, runtime startup on iPhone, actual Files import, AVAudioUnitEQ/Delay, two independent file playback and live recording to WAV have **not** been executed on an Apple platform.
3. The approximate BPM analyzer is known to confuse half/double tempo on dense hats (96 vs 192). File-deck SYNC/time-stretch, scratch, accurate phrase AutoMix, commercial-track STEMS, reliable loop engine, real sample-based TrackBuilder and full compatibility/key analysis remain unimplemented.
4. Performance, route recovery, thermal/latency/xrun measurements, microphone/headphone/Bluetooth behavior, screen safe areas/accessibility require **physical iPhone QA**. C++ sanitizers are not a replacement.
5. Avoid calling this `release`, `10 releases` or `TestFlight ready`. It is one source update comprising **multiple individually verified engineering checkpoints**.

## Next semi-release readiness criteria

- Apple simulator build green; launch and no immediate crash.
- Physical iPhone: import 2 WAV/MP3 files; independent PLAY/PAUSE/CUE/Hot Cues; EQ and ECHO audible; crossfade A→B; capture genuine master audio to file; reopen exported file in Files; verify no dropped audio frames.
- User approval should be sought only **after** this semi-release gate is genuinely met.

## Portable performance measurement

On this Linux x86_64 container only, `benchmark_core` rendered 12 virtual seconds of stereo synthesis, 2 decks, EQ and echo in 0.04s at 48kHz, 0.14s at 96kHz and 0.46s at 192kHz, i.e. ~323x, ~88x and ~26x real time respectively. These are *not* iPhone results, cannot establish real-time worst-case thread deadline compliance, and exclude imported-file AVFAudio processing. Do not extrapolate to device energy/thermal behavior.
