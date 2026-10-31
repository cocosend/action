# DJ TrackBuilder MixAuto Pro — 0.5.2 current source gate

> Route-loss/interrupt safety, cancellation propagation, and allowlisted ZIP packaging were fixed and regression-tested on Linux. See [0.5.2 engineering checkpoint](ENGINEERING-CHECKPOINT-0.5.2.md). **No Apple SDK or iPhone test has been performed. This is not an IPA or TestFlight.**

---

# DJ TrackBuilder MixAuto Pro — current release gate 0.5.1 (2026-10-28)

> **Source-only checkpoint. Not an installable iOS semi-release.** 0.5.1 adds headphone-loss pause, detached-worker cancellation propagation, safe import cancellation cleanup and a corrected iOS bundle version. Full detail: [0.5.0 engineering](ENGINEERING-CHECKPOINT-0.5.0.md). All Apple SDK, device and signing gates remain blocked.

| Gate | State | Evidence |
|---|---|---|
| C++ Release tests | **PASS 5/5** | Real synth/dual-deck/EQ, stereo spectral waveforms, original voice mute/solo, live recording ring |
| C++ Clang ASan / UBSan / leak | **PASS 5/5** | Compile and execute all 5 binaries |
| Swift portable models | **PASS** | 11 model/audio metadata and timing suites incl grids, cue, file-loop and beat-hint |
| SwiftUI / Apple frameworks | **NOT VERIFIED** | Linux syntax parse only, no Xcode SDK |
| Native A/B file playback, loop, EQ, live recording | **SOURCE CODE EXISTS — UNVERIFIED** | Requires Xcode, simulator, physical iPhone |
| True file STEMS, scratch, pitch-preserving SYNC, phrase-aware mixing | **NOT IMPLEMENTED** | Cannot truthfully claim working |
| Original Canva fidelity | **IN PROGRESS** | First approved visual unchanged; no device screenshots compared |
| GitHub isolated native CI, signing, IPA, TestFlight | **NOT VERIFIED / NOT PROVISIONED** | No independent repo or Mac access |

Only request user approval at a real audio-verified, installable semi-release. Do not treat a source ZIP as release.

---

# M1.8 Alpha 0.3.3 — factual readiness (2026-10-28)

| Gate | Current state | Evidence and limitations |
|---|---|---|
| C++ Release build & regressions | PASS | 2 CTest binaries, includes sample-clock/BPM, bank, level, EQ, 8–192 kHz, independent deck audio gates, pattern automix, concurrent control |
| C++ ASan & UBSan | PASS | Sanitizer runs completed in current environment |
| Swift Foundation model + tempo tests | PASS | Project backwards-compatibility for added EQ + import manifest path validation |
| SwiftUI/AVFAudio source syntax | PASS | `swiftc -frontend -parse`; **not a full typechecked Apple build** |
| File player & import code | IMPLEMENTED, UNVERIFIED ON IOS | Security-scoped import, AVAudioFile validation, persistent copied local file, per-deck AVAudioPlayerNode and EQ; requires Xcode/device test |
| Separate deck play/cue | IMPLEMENTED, UNVERIFIED ON IOS | Pattern deck gates in C++ verified; audio file Play/Pause/Cue requires physical verification |
| Visual layout conformance | IN PROGRESS | Original first Canva nine slides remain reference; no simulator screenshot or on-device QA performed |
| Imported-file BPM hint | IMPLEMENTED, NOT IOS VERIFIED | PCM off-thread analysis, algorithm tested on synthetic rhythms and real C++ 138 BPM demo. Optional conservative estimate; unreliable tracks remain UNKNOWN. |
| Offline beat-phase hint | IMPLEMENTED, NOT IOS VERIFIED | 10ms-energy onset candidates + bounded tempo refinement, only when BPM and rhythmic evidence pass gating; optionally persisted. A displayed `BEAT GRID · APPROX` is explicitly not beat/phrase-SYNC. |
| Accurate beatgrid/phrase/SYNC/key | NOT IMPLEMENTED | Approximate beat-phase metadata is **not** a production-accurate grid with downbeat/phrase or elastic time stretching. File SYNC remains disabled. |
| Imported-song phrase-aware AutoMix | NOT IMPLEMENTED | Pattern AutoMix only; guard prevents using file decks |
| Advanced FX, four-channel STEMS, vinyl scratch | NOT IMPLEMENTED | Not falsely represented as working |
| Live mix recording | NOT IMPLEMENTED | 16-second offline pattern-render WAV only |
| Xcode simulator build, signing, device playback, IPA | NOT VERIFIED | No connected macOS / Xcode tool or separate GitHub repo currently available |
| GitHub CI on new native repository | NOT RUN | GitHub connector supports editing repos, not creation of isolated new native repo |

## Semi-release gate

A user acceptance checkpoint is appropriate **only after** native Xcode succeeds, physical device audio and imported file workflows are verified, the approved visual is compared against actual screenshots, and a TestFlight/ad hoc distribution path is secured. This source ZIP does **not** cross that gate.

## M1.6 Alpha 0.3.1 extra evidence

- 6 controlled input tempos (78, 96, 120, 128, 145, 174 BPM): estimated within 2.8 BPM at 100 energy samples/s. A synthetic fast BPM initially yielded a half-speed alias; harmonic resolution was corrected and regression-tested.
- All-zero envelope, non-finite envelope, unstructured noise and shorter-than-10-second audio: no fabricated BPM result.
- The actual independently rendered C++ 16 s pattern/mix audio (nominal 138 BPM, 48 kHz stereo PCM16) is estimated at **139.5 BPM** with heuristic confidence >0.74. This is an audio file regression, not proof of accuracy for arbitrary commercial songs.
- The UI only shows `~value` and `BPM · ESTIMATE` for cached high-confidence import results; otherwise `ANALYZING`/`UNKNOWN`. Accurate track sync, beatgrid and source timing are **still excluded**.
- Simulator/Xcode/iPhone playback remains unavailable in this Linux session; release gate remains blocked.

## M1.8 Alpha 0.3.3 extra evidence

- Added pure Swift Foundation `BeatGridAnalyzer` that detects the **first beat phase** and period of a bounded audio excerpt only after the conservative BPM estimator has accepted the signal. The period is refined around the lag-quantized BPM hint to reduce drift. It does **not** know the time-signature downbeat, phrase, key or track synchronization.
- 12 deliberate tests on 78, 96, 120, 128, 145, 174 BPM with 120ms and 240ms starting offsets, periodic with offbeat hi-hats: period error <14ms and cyclic phase error <60ms. Zero audio, noise and low-confidence BPM do not fabricate grids.
- A track with 96 BPM plus rapid offbeat hats is sometimes read as 192 BPM by the upstream tempo analyzer; both are musically ambiguous interpretations. The app must not auto-SYNC based on such an unverified estimate. An estimate alone is not an acceptance test on commercial material.
- Added optional `beatGrid` to file manifest, with old-JSON migration tests and consistency validation to stored tempo; rendered overlay lines appear **only when real phase data are available**. Arbitrary `8 lines` in the prior file waveform are removed.
- The 16s PCM WAV generated by the independent C++ core gives 139.5 BPM and an optional approximately 0.435s beat interval in the Swift test.
- The Xcode/iPhone, phase drift on non-static-BPM recorded material, time stretching, file playback/Sync and true master recording are still unverified/unimplemented.

## M1.8 Alpha 0.3.3 extra evidence

- Manual GRID editor per imported Deck A/B, with reversible BPM display and first-beat offset. The editor writes a new validated import-manifest snapshot *before* updating the observed deck metadata. It never changes live file transport, resamples sound or claims synchronized playback.
- A user override sets `manuallyAdjustedGrid` and tempo/phase `confidence=0` to distinguish human entry from measured certainty. Older JSON manifests lacking these optional fields are still accepted.
- A stale background tempo analysis cannot overwrite user edits: identity guard now compares the full imported metadata snapshot, not only the file basename.
- Standalone Foundation tests cover correction 192 → 96 BPM, persistence, missing-analysis manual entry and invalid/nonfinite values. No Apple SDK run or physical deck test is claimed.
