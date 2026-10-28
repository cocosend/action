# DJ TrackBuilder MixAuto Pro — source checkpoint 0.6.1 (Xcode build blockers corrected)

The **FIRST approved nine-page Canva** design is the only visual target: [open the canonical concept](https://www.canva.com/d/UoJgnHMYH-EJu2u). The later redesign is rejected. This is a separate project from Stripewolf Wave, ARTSS DJ Creator and DJ NOVA.

**Project state: SOURCE ONLY.** No separate GitHub repo, signed IPA, device installation, published URL or verified iPhone playback exists. The completed portable Linux tests below cannot prove Core Audio runtime behavior.

## What this source currently contains

- C++17 real-time dual-deck synth sequencer with four 16-step pattern banks, original Kick/Hat/Bass voices, velocity, swing, smoothed EQ/filters/echo, crossfader and Pattern AutoMix.
- SwiftUI iPhone-first DJ Cockpit following the graphite/cyan/coral original Canva identity, two distinct decks with vertical PCM-derived **5-band spectral waveform energy**, fixed transport and mode rail.
- Native iOS file-deck sources with AVAudioPlayerNode, EQ/delay, file import, play/cue, **eight live Hot Cues per deck**, sample-segment seek and bounded file loops (4/8/16 approximate beats); Apple runtime **unverified**.
- Beat hint estimate, grid correction, conservative unwarped file transition and immediate manual fader takeover. **These do NOT provide pitch-preserving Sync or phrase-aware beat matching.**
- Real mute/solo for *synthesized Kick/Hat/Bass* on each deck. **Imported-song four-channel STEMS NOT available.**
- Native mixer WAV recording pipeline and offline original-pattern WAV render. Native recording runtime **unverified**.
- JSON project store, backwards-compatible audio manifests, off-callback waveform analysis, C++/Swift automated tests and macOS simulator GitHub Actions template.

## Verify portable code

```bash
scripts/verify_linux.sh
```

Checks 5 Release C++ suites, 5 Clang sanitizers suites, portable Swift Foundation model/algorithm tests (including route safety and background cancellation), Swift syntax parsing and real 16-second WAV format/peaks. No connected Mac/Xcode or physical iPhone available in this environment.

## Build and exercise real Apple Audio Units on a Mac

Version 0.6.0 introduces an XcodeGen XCTest **integration target** using Apple's
actual `AVAudioEngine` in offline/manual mode. It feeds **two independently
scheduled audio files into EQ/Delay/mixer** and verifies nonzero PCM output;
a second test checks repeated AVAudioPlayerNode `.loops` output. XCUITest UI
smokes open WAVE/MIX/STEMS/BUILDER/FX/AUTO and save simulator screenshots. These
checks are **prepared but have not been executed**, since no macOS host is
connected. They cannot prove iPhone audio latency, speaker routing or master
recording.

From the source root on any appropriately configured Mac with Xcode + XcodeGen:

```bash
scripts/ios_build_on_mac.sh
```

It produces `ios-build-results/` with a **simulator-only unsigned `.app`**, XCTest
result bundle, test logs and the cockpit screenshot. The file is **not an IPA**
and cannot be installed on a physical iPhone. The same test matrix runs in
`.github/workflows/ci.yml` when this project has its OWN isolated GitHub repo.
No other DJ app repository should be used as a substitute.

## Alternative manual simulator build on Mac

```bash
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -project DJTrackBuilderMixAutoPro.xcodeproj \
  -scheme DJTrackBuilderMixAutoPro \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Then validate both imported decks, file loops, live WAV recording, accessibility and route changes on an actual iPhone. The Xcode build commands are **instructions**, not proof they succeeded.

## Safety and reliability corrections in 0.5.1

- Headphone or Bluetooth output disconnect pauses all decks **even if the output sample rate is unchanged**. Any live recording is stopped safely; the user must explicitly tap PLAY again.
- Long-running waveform/tempo/file-loop/import/export work now propagates parent cancellation into its detached worker to avoid stale CPU load, waveform data, and unnecessary disk work after a deck changes.
- Import destination path is reserved on the owning task; a canceled/failed background file copy is cleaned up rather than being left as an orphan.
- iOS bundle and CMake versions are aligned at **0.5.1**. Sanitized CMake build directories are excluded from the source ZIP and cannot inflate or leak binaries into delivery.

## Project docs

- [0.5.1 reliability fixes, safety and tests](docs/RELIABILITY-FIXES-0.5.1.md)
- [0.5.2 route safety, cancellation and packaging](docs/ENGINEERING-CHECKPOINT-0.5.2.md)
- [0.5.0 engineering and evidence](docs/ENGINEERING-CHECKPOINT-0.5.0.md)
- [Release readiness and missing Apple runtime gates](docs/RELEASE-READINESS.md)
- [First Canva visual conformance matrix](docs/APPROVED-CANVA-CONFORMANCE.md)
- [Core audio architecture](docs/ARCHITECTURE.md)
- [0.4.0 historical checkpoint](docs/ENGINEERING-CHECKPOINT-0.4.0.md)

## Checkpoint packaging

```bash
python3 scripts/package_source.py /path/to/DJ-TrackBuilder-MixAuto-Pro-0.5.0-Source-Checkpoint.zip
```

The source-only ZIP includes a `SOURCE_SHA256SUMS.txt` manifest and excludes generated build directories, artifacts and private credentials. No paid/third-party music or third-party DJ artwork is bundled. Do **not** request release approval until Xcode, iPhone sound, navigation and original Canva visual QA are actually proven.


### Current 0.6.0 validation status

Portable DSP and Swift Foundation tests: run `scripts/verify_linux.sh`.
Apple's audio graph integration tests and SwiftUI UI smoke: **not run on this
Linux host**; GitHub Actions macOS template and local one-command Mac script
are supplied. A real installation requires signing/provisioning after those
builds pass. Preserve the first nine-page Canva design as sole visual target.


## 0.6.1 Xcode gate corrections

- `SWIFT_VERSION` uses the supported Swift 5 language compatibility mode (`5.0`) instead of an unsupported toolchain-specific `5.9` string. Modern Swift compiler remains selected by installed Xcode.
- A `#if DEBUG`-only deterministic dual-file fixture is loaded **exclusively** for an explicit `--mixauto-ui-seeded` XCUITest launch argument. CI tests actual imported-file UI, persistence, two player controls, and Hot Cue activation without relying on a Files picker. Ordinary release/user data is unaffected.
- The UI test opens the Hot Cue `Menu` before selecting pages 5–8, correcting an impossible control lookup.
- Apple's audio graph test helper was renamed so XCTest does not interpret a returning factory method as a test.
- Temporary CI branch `mixauto-ios-ci` is eligible to run this workflow as a staging lane, without changing another project's default branch. A proper standalone repository remains the production target.

**These changes are prepared, not proof of an iOS runtime build until GitHub-hosted macOS tests return successful runs.**
