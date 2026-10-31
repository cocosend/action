# DJ TrackBuilder MixAuto Pro — 0.5.2 transport and background-work hardening

Date: 2026-10-28  
Reference: first approved 9-page Canva design only (https://www.canva.com/d/UoJgnHMYH-EJu2u).  
Status: **source-level checkpoint only**. No signed IPA, TestFlight, simulator or iPhone verification.

## Actual changes

1. **Headphone/Bluetooth output removal safety.** The session route-change handler now distinguishes unavailable output, old output lost, output connection and non-safety configuration changes. The player pauses when a previously used output disappears **even if the new device reports the same 48 kHz sample rate**. `noSuitableRouteForCategory` is also treated as a loss. Reconnecting an output never automatically resumes a stopped mix. A concurrent sample-rate change still forces teardown and reinitialization on next user gesture. The policy is portable and unit-tested; AVAudioSession notification delivery requires Apple-device validation.
2. **Interruption transport position.** The AVAudioSession interruption path now captures each file's current sample frame before pausing its player node, rather than relying on potentially-invalid `lastRenderTime` after the AVAudioEngine has stopped. Recovery is explicit, not automatic. A live recording is stopped and drained before the mixer pauses.
3. **Cancellation of expensive background analysis.** A dedicated `BackgroundWork.run` boundary forwards parent cancellation into its detached utility worker, rejects pre-canceled callers *before scheduling work*, and checks cancellation again before publishing a result. Pattern rendering checks between 512-frame chunks; file waveform decoding and tempo analysis check between 4096-frame chunks. A cancelled analysis therefore stops at the next bounded chunk rather than continuing to process the remainder of a multi-hour file. Regression tests include cancellation during work, cancellation before launch and error propagation. None of these operations is on the real-time Core Audio render thread.
4. **Distribution safety.** Previous source packaging had a broad directory-walk exclusion list that could accidentally include newly named directories such as `.build-sanitized`. Packaging now uses a strict source-file allowlist by directory + extension, excludes symlinks, verifies each ZIP entry's SHA-256 and tests that CMake/sanitizer binaries and unapproved credential files are never bundled. This fixes a *real packaging defect* noticed during this checkpoint.
5. **Repeatable verification.** `scripts/verify_linux.sh` now exercises the route, cancellation and package regression suites in addition to existing audio/model tests. To run a quicker portable-only pass, use `MIXAUTO_SKIP_SANITIZERS=1 scripts/verify_linux.sh`; default remains sanitizer-enabled.

## Automated evidence actually obtained

- C++ Release CTest: **5/5 PASS** (patterns, dual deck, EQ/delay, spectral energy and master capture ring).
- Clang AddressSanitizer + UndefinedBehaviorSanitizer with leak detection: **5/5 PASS**, using the existing dedicated sanitized build directory.
- Swift 6 strict-concurrency compilation and execution of `AudioRoutePolicyTests.swift` and `BackgroundWorkTests.swift`: **PASS**.
- All available portable Swift Foundation/metadata/audio timing model tests: **PASS**; native iOS Swift files **syntax-parse only** on Linux.
- Existing generated test WAVs validated: 48 kHz stereo 16 seconds, nonzero RMS, no full-scale clipping, stem mute/solo energy changes as expected.
- Cryptographically verified allowlisted source package: **PASS** (ZIP SHA-256 computed at packaging time).

## Not yet verified or not implemented

**No macOS/Xcode host is connected.** Apple SDK type checking, real AVAudioSession callbacks, real USB/Bluetooth speaker/headphone removal, AVAudioPlayerNode loop/routing, AVAudioUnitEqualizer/delay and mixer tap WAV writer on iPhone are not tested. No `ipa`, signed app, TestFlight or release URL. The original Canva nine-slide visual reference has no actual iPhone screenshot comparison. True pitched file SYNC, key/downbeat/phrase analysis, four-part separated imported song stems and responsive vinyl scratch are not present as production features.

### Required physical-device test matrix

- iPhone + wired or Bluetooth headphones: start file A/B and master recording. Disconnect while playing; **expected:** audio stops, file position persists, recording stops safely, no speaker burst or automatic restart.
- Repeat with unchanged 48 kHz route and changed 44.1/48 kHz route; verify no render-core use-after-free and explicit next-gesture reinitialization.
- Start a very long imported file's waveform analysis and rapidly import a different file; verify earlier decode is cancelled, no stale waveform is published and no UI freeze occurs.
- Check interruption by phone call / system audio and foreground return; file resumes from the captured frame after explicit tap.
- Capture actual A+B WAV recording, inspect channel count/format/duration and dropped-frame warning.
- Run full UI/safe-area, 60/120fps and original Canva cockpit comparison.
