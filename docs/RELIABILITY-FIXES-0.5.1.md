# Reliability correction 0.5.1 — source-only engineering checkpoint

**Date:** 2026-10-28  
**Project:** DJ TrackBuilder MixAuto Pro (separate from the other DJ apps)  
**Visual baseline:** FIRST approved Canva, 9-slide edition, design `DAHZSQ90Bqg`; no visual redesign or Canva edit.

## Corrected defects

1. **Output disconnection safety.** A headphone or Bluetooth output loss often does *not* change the session sample rate. Previously the route notification returned early when the old and new sample rates matched, potentially leaving the mix playing on the phone speaker. `AudioController.handleRouteChange(_:)` now recognizes `.oldDeviceUnavailable` and pauses all decks and live capture independently of sample-rate change. Preserves the playback position where possible and requires another explicit PLAY gesture.
2. **Background cancellation.** A child created with `Task.detached` is unstructured: cancellation of the parent task does not automatically reach the child. Previously, obsolete waveform / tempo decoding could outlive a deck change and waste CPU. Added `BackgroundWork.run` with a cancellation handler to propagate cancellation to the worker; replaced five direct detached calls (waveform, tempo, file-loop, file-import and offline-export). The analyzer already checks `Task.isCancelled` inside its sample loops. A final cancellation guard prevents publishing stale waveforms.
3. **Canceled import cleanup.** The app-owned destination filename is now allocated by the parent import task and retained throughout the operation; if the background copy fails or the parent is canceled, cleanup can find and remove the partially copied file. File extension is restricted to an alphanumeric suffix or falls back to `.audio`.
4. **Version identity.** Fixed the stale Info.plist version `0.4.0` in a source checkpoint that was already `0.5.0`. Info.plist and CMake now identify the corrected `0.5.1` source checkpoint.
5. **Source package hygiene.** The ZIP packager now excludes *all* `.build*` folders, including `.build-sanitized`, so sanitizer binaries and intermediate files cannot be bundled as source.

## Verification evidence on Linux

- Portable Swift 5.9-compatible `AudioRoutePolicyTests`: **PASS** (headphone loss with unchanged sample rate, invalid sample rate and ordinary route changes).
- Portable `BackgroundWorkTests`: **PASS** (parent cancellation is observed by the detached worker and results in cancellation), tested again under **Swift 6 `-strict-concurrency=complete`**.
- C++ Release CTest **5/5 PASS**: Audio DSP, advanced controls, original synth stem gates, stereo spectral envelope, capture ring.
- Clang combined AddressSanitizer + UndefinedBehaviorSanitizer + leak-check CTest **5/5 PASS**.
- Existing portable Swift suites for TempoAnalyzer, BeatGridAnalyzer, BeatGridEditor, Hot Cues, AnalysisMergePolicy, BeatHintTransition, FileLoopPlan, TimedBlendPlan, TempoCompatibility and TrackProject **PASS**.
- Every iOS Swift file **syntax-parsed**, **not** typechecked against Apple's SDK.
- Info.plist XML and version fields checked with Python's `plistlib`.

## Remaining hard blocker — do not claim release

A GitHub repository for this *separate* app is not yet present in the connected account, and the GitHub connector in this chat has no repository-creation operation. There is no connected Mac in Remote Desktop Commander; local environment is Linux without Xcode. Thus **no full SwiftUI/AVFAudio/Xcode compilation, simulator run, native playback, on-device recording, signature or TestFlight** was performed.

The existing `.github/workflows/ci.yml` includes a macOS simulator build and the new portable route/cancellation tests. It can only run after the user has an independently provisioned repository and GitHub Actions permissions; that CI configuration is not proof of a successful iOS build. No modification to another DJ repository was made to bypass project isolation.

Real track tempo sync/stretch, phrase-aligned AutoMix, vinyl scratch and imported-song stem separation remain unimplemented. This remains a **source checkpoint, not a semi-release**. The first approved Canva visual direction is unchanged.
