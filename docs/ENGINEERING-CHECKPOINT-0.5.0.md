# DJ TrackBuilder MixAuto Pro — engineering checkpoint 0.5.0

**Date:** 2026-10-28  
**Scope:** independently packaged native iOS/SwiftUI + C++ source, not a signed iPhone application.  
**Canonical UI reference:** [FIRST approved nine-slide Canva deck](https://www.canva.com/d/UoJgnHMYH-EJu2u), design ID `DAHZSQ90Bqg`. Rejected later redesign is not a source of truth.  
**Previous source:** 0.4.0 source checkpoint; all previous two-deck, recording and cue source retained.

## Delivered increments in one engineering pass

| ID | Source-level feature | Portable evidence | Still needs Apple runtime QA |
|---|---|---|---|
| 0.5-A | **Actual five-band spectral waveform intensity** for original synth and imported audio files. C++ streaming spectral envelope computes five first-order frequency regions per time bin; it doesn't fabricate spectral colors from only peak amplitude. Separate L/R energy prevents anti-phase stereo cancellation. | `SpectralEnvelopeTests.cpp` verifies 60/900/10000 Hz, one-sample vs 511-frame chunks, phase-inverted stereo, invalid inputs, silence/NaN | `AVAudioFile` decode on iPhone, waveform performance and exact screen position |
| 0.5-B | **Conservative beat-hint automatic file transition**. Starts unwarped native file fade only if both decks have accepted measured/manually corrected grids, near-identical BPM, enough tail, and a cued second deck. Uses off-audio-thread timer and declares approximation; not time stretching, phase lock or phrase matching. | `BeatHintTransitionTests.swift`: 4/8/16/32-beat cases, invalid grid, low lead/EOF, excessive tempo drift, duration | `AVAudioPlayerNode` start accuracy and audible real-file overlap; latency can be up to scheduling jitter |
| 0.5-C | **Real PCM file loops** on Deck A or B from approximate beatgrid. Loads a bounded 4/8/16-beat segment asynchronously; resamples to output rate when needed and schedules `AVAudioPlayerNode` loop buffer. Loop is persisted in a backward-compatible file manifest, can be exited without replacing the track, and is invalidated safely by replacement/seek. | `FileLoopPlanTests.swift`: snap, duration limits, source PCM bounds, persistence and malformed data | Apple SDK compile, AVAudioConverter, loop playback and click-free transitions on hardware |
| 0.5-D | **Real original-pattern voice mute/solo** (3 synthesizer voices Kick/Hat/Bass *per deck*). No false claim of commercial song stem separation; live `STEMS` screen can mute/solo only source synth voices; loaded commercial songs show an explicit unavailable state. | `PatternStemControlsTests.cpp`: audible difference, solo precedence, smoothing, invalid indices. `TrackProjectTests.swift`: JSON roundtrip and backward migration | SwiftUI target layout and real device touch/performance QA |
| 0.5-E | **Instant single-tap Hot Cues**, while long-press opens set/clear menu. Previously the `Menu` required an extra selection even during performance. | File cue state model tests PASS; Swift view source parses | Actual iPhone accessibility, tap/long-press priority and end-of-file playback QA |
| 0.5-F | **Improved compiler and DSP safety**. Multi-sample-rate tests, `ASan+UBSan+leak` and stereo phase-inversion regression; sanitized target build uses one worker to avoid CI container resource contention. | Portable CTest 5/5 PASS, sanitized CTest 5/5 PASS, Swift model tests PASS | Full Xcode compile still not run |

## What the engine actually does

- Deck A and Deck B have independent AVAudioPlayerNode file paths (iOS only) and independent original synth decks in C++, crossfader, EQ and echo/delay source.
- Waveform display uses real **audio-dependent approximate spectral energy**; no FFT precision, actual vocals/drums/music separation or claim of accurate musical key.
- BPM estimate, first-beat hint, manually edited grid and loop start are heuristics; explicit `BPM UNKNOWN`/unavailable states protect against invented analysis.
- Native file loop performance relies on Apple `AVAudioPlayerNode.scheduleBuffer(..., options: [.loops])` and conversion of non-native sample rates to the engine output format; neither has been tested in Apple runtime here.
- The `STEMS` screen has **working C++-tested original pattern mute/solo**; imported songs do **not** have 4 isolated stems. Pattern voice mute/solo values persist in project JSON.
- Beat-hint mixing is **not** musical key/phrase analysis, phase-accurate sync or pitch-preserving time stretch. The user can take over through crossfader at any time.

## Automated verification — reproducible locally

```bash
scripts/verify_linux.sh
```

**Verified on Linux with Swift/Clang/CMake:**
- Release: 5 C++ CTest binaries, all PASS.
- Clang ASan/UBSan/leak: 5 C++ CTest binaries, all PASS.
- Swift pure-Foundation tests: project migration, audio manifest validation, BPM estimate, onset/beatgrid, grid edits, hot-cue model, analysis merge, timed blend, beat-hint plan, file-loop plan, tempo compatibility — PASS.
- SwiftUI/AVFAudio source only syntax-parsed; cannot type-check Apple frameworks from Linux.
- Original 16-second pattern/crossfader/EQ WAV **and 16-second original synthetic voice mute/solo WAV** verified for stereo 48kHz PCM16, correct duration, nonzero audio and no full-scale clipping. **This does not verify live iPhone recording**.

The new voice mute/solo WAV shows four real stages: full original pattern (0–4s), Bass muted (4–8s), Hat solo (8–12s), restored full pattern with Echo (12–16s). An automated RMS check confirms audible changes in each stage and no clipping. This validates only synthesized voices, not separated commercial file stems.

## Blockers to an actual installable iOS semi-release

1. Standalone repository with working **macOS Xcode simulator CI** is not provisioned. No macOS device connected to ChatGPT. The code archive is not an IPA or hosted web application.
2. Apple SDK Swift type-check, AVAudioPlayerNode scheduling, conversion, Audio Unit EQ/delay, Core Audio live recorder, audio session route/interruption and Files import are **unverified**.
3. No physical iPhone checks for headphone routing, CPU, touch targets, waveform frame pacing, actual file loops or live mix recording, nor screenshot comparison to canonical Canva.
4. Pitch-preserving SYNC, verified phrase-aware MixAuto, DJ scratch/jog and **four-channel file STEMS** not implemented. Disabled/unavailable controls must remain honest.
5. Do not request user approval until a functional, installable test build can be checked against the original first Canva design on iPhone.

**No edits to the original Canva or existing unrelated GitHub DJ projects.**
