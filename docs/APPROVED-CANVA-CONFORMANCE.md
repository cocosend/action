> **0.5.0 update:** Waveforms now derive five frequency bands from real stereo PCM samples rather than applying a decorative amplitude color gradient; antiphase stereo is tested. File cues are one-touch with long-press editing. Pattern-only Kick/Hat/Bass STEMS have real mute/solo; separation of imported vocals/music is still unavailable. 4/8/16 beat loop menus and approximate beat-hint file blend exist in source. These are not Xcode/iPhone-verified and screenshot fidelity to the FIRST Canva presentation has not been measured. See [0.5.0 engineering](ENGINEERING-CHECKPOINT-0.5.0.md).

# Approved Canva visual conformance — engineering matrix

**Canonical original:** [DJ TrackBuilder Pro — original Canva design](https://www.canva.com/d/UoJgnHMYH-EJu2u), source design ID `DAHZSQ90Bqg`, 9 pages.

**Rejected visual redesign:** the v0.4 Canva addendum must **NOT** be used as the visual target. The user explicitly requested the original design. This matrix tracks correspondence to the first design without pretending simulator/iPhone screenshot comparisons have been performed.

| Design element from the approved Canva concept | v0.3.1 source status | Verification required |
|---|---|---|
| Matte charcoal immersive shell | **Implemented in SwiftUI** | Screenshot pixel QA on real device |
| A left / B right track headers, distinct identities | **Implemented** | iPhone 390 and 430 widths, long artist/file titles |
| Two large vertical multicolor waveform displays | **Implemented from measured PCM peaks** | Render output, frame pacing, zoom, waveform alignment |
| Fixed playhead and grid visualization | **Visual-only grid; no BPM beatgrid for imported files** | Must not mistake decorative grid for real beat grid |
| Persistent mode rail, PLAY/CUE/SYNC/crossfader | **Implemented as a stable rail** | Safe areas, hit targets, VoiceOver; SYNC disabled until actual implementation |
| Independent deck PLAY and imported file CUE | **Implemented in code** | Physical iPhone audio verification / file EOF |
| EQ/MIX three-band controls + filter/gain | **DSP and Audio Unit implementation** | Frequency sweeps, click-free sound and clipping tests on device |
| Original pattern Builder + live pads | **Existing audio functionality retained** | Touch gestures and real audio timing |
| Smart FX grid (Riser, Gate, Echo, Phaser, etc.) | **Not implemented** | Requires DSP/FX spec and implementation, do not show fake live controls |
| Four-channel STEMS (DRUMS/BASS/VOCALS/MUSIC) | **Not implemented** | Analysis models, latency, separation licensing |
| Vinyl jog/scratch | **Not implemented** | Decide source PCM/sample interpolation and touch-to-audio behavior |
| BPM hint for imported songs | **Conservative PCM-onset analysis implemented; `~BPM` only** | iPhone validation of file reading, uncertain estimates and truthfulness |
| Accurate beatgrid, key and SYNC for imported songs | **Not implemented** | Robust beatgrid/phase, key analysis and pitch-preserving time stretching |
| MixAuto with phrase-aware plan for full file tracks | **Not implemented** | Beatgrid/phrase/confidence and manual handoff; current Pattern AutoMix works on common pattern clock only |
| Real mix REC/stream output | **Not implemented** | True master capture, WAV metadata/level and file ownership |
| Landscape dual-deck layout | **Not implemented** | Landscape geometry & device testing |

## Hard release criteria (not waived)

1. Build with Xcode and full Apple SDK, then run on physical iPhone.
2. Measure per-deck file import/play/pause/cue/EOF with WAV/MP3/M4A and error cases.
3. Validate separate deck controls, fader audible effect, EQ filter response and no unintended silence/clipping.
4. Test interruptions, route changes, Bluetooth/USB, background/foreground, sandbox file persistence.
5. Compare actual screenshots against the **original** Canva presentation only. Fix text truncations and touch area violations without redesigning the approved layout.
6. Obtain a user decision only at the announced semi-release gate. Do not imply an installable build exists before signing/distribution.
