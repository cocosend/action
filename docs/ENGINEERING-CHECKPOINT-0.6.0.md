# DJ TrackBuilder MixAuto Pro 0.6.0 — Apple simulator gate prepared

**Status: SOURCE ONLY, not a signed iPhone application.**
**Canonical visual:** first original nine-slide Canva design https://www.canva.com/d/UoJgnHMYH-EJu2u . The rejected alternative redesign is excluded.

## Engineering changes actually completed in source

1. Added an independent XcodeGen **iOS UI automation target**. It launches the real native SwiftUI app, verifies the A/B transport, crossfader, disabled unavailable file SYNC, navigates WAVE/MIX/STEMS/BUILDER/FX/AUTO, checks Hot Cue control availability, and attaches original-cockpit screenshots as XCTest artifacts.
2. Added a separate Apple **AVAudioEngine audio integration target** (not a mock): generates two original stereo audio files, connects two AVAudioPlayerNodes through EQ and delay units to a real AVAudioMixerNode, renders it in Apple's offline manual mode and asserts non-silent, finite, bounded PCM. A second integration test asserts `.loops` continues emitting audio after the source buffer duration. This checks the graph on a macOS-hosted iOS Simulator, **not physical output latency or audio-session routing**.
3. GitHub Actions macOS test job now installs/boots an available iPhone simulator, builds via XcodeGen/Xcode, runs unit+UI tests, captures a cockpit screenshot and uploads unsigned `.app` plus `.xcresult` artifacts **only when an isolated repo runs the workflow**. It cannot sign a production IPA or distribute TestFlight.
4. Added `scripts/ios_build_on_mac.sh`, a one-command reproducible Mac run that generates an Xcode project, builds, executes native tests, captures a screenshot and creates an unsigned simulator-app ZIP.
5. Fixed file-import cancellation race: a switch back to original patterns invalidates an in-flight security-scoped file copy. The finished detached worker cannot silently replace the chosen deck. The canceled copy is cleaned up and cannot publish metadata. Pure Swift generation-policy tests cover active/stale/deck mismatch/invalid indices.
6. Set app + CMake source version to 0.6.0 and made source packaging include both Apple-only test targets and Mac build script; manifest SHA-256 protection retained.

## Tests performed here (Linux, 28 October 2026)

| Test | Result |
|---|---|
| Prebuilt C++ Release CTest five suites | **PASS 5/5** (C++ production source unchanged) |
| Prebuilt C++ ASan/UBSan/leak five suites | **PASS 5/5** (unchanged C++ core) |
| Swift `ImportCommitPolicyTests` | **PASS** |
| Swift syntax parse: all app, UI tests, AudioGraph tests | **PASS** (NOT Apple SDK type checking) |
| XcodeGen YAML, GitHub workflow YAML, iOS Info.plist | **PASS parse/structure** |
| `bash -n` Mac/portable scripts | **PASS** |
| Strict allowlisted source packaging, ZIP CRC, SHA-256 manifest | **PASS** |
| Previous portable Swift tempo/beatgrid/loop/route/background tests | **PASS in prior completed run**; a fresh full rerun in this session was interrupted by execution time limits during sanitizer rebuild or WAV tempo stage, so **NOT a fresh whole-suite PASS** |
| Full Xcode/Apple SDK Swift type check | **NOT RUN: no macOS** |
| Native iOS Simulator XCUITest / Apple AudioGraph offline tests | **NOT RUN: no macOS** |
| Physical iPhone A/B, mix recording, interruptions, latency, UI screenshots vs Canva | **NOT RUN** |

## Environment gate checked

GitHub connector repository search found **no independent `DJ TrackBuilder MixAuto Pro` repository**, and GitHub actions available in connected app do not include new-repo creation. Desktop Commander connected device list is **empty** (no Mac). Editing the user’s existing ARTSS/Stripewolf DJ repositories to bypass this would violate the explicit project isolation requirement. Therefore neither existing GitHub CI nor physical Xcode build was invoked. **Do not label this release or claim installability.**

## Exact next executable gate

Once an independently provisioned GitHub repo is connected, push *only* the packaged files to that repository. Its `.github/workflows/ci.yml` macOS job attempts a full simulator build/test and publishes an unsigned simulator ZIP and screenshots if it succeeds. Alternatively, on a Mac with Xcode and XcodeGen installed, run `scripts/ios_build_on_mac.sh` from the extracted source root. Fix any actual Apple-SDK errors and UI test failures then verify real iPhone playback and signing. Stop calling source archives semi-releases until this gate passes.
