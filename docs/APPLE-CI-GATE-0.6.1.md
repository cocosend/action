# 0.6.1 — native Xcode build and functional UI gate

The source is still not a signed IPA or an app that has been installed on a physical iPhone.

## Repaired Apple-specific test blockers

- `SWIFT_VERSION` set to `5.0` for supported Swift 5 language mode. The actual compiler is Xcode's installed toolchain, **not** Swift 5.0 from 2019.
- Main app includes `DebugUITestFixture.swift`, compiled only in Debug and activated only by `--mixauto-ui-seeded`. It writes two original PCM tones as application-owned CAF tracks with real metadata, then the ordinary AudioController loads them. Normal launches and App Store builds do not seed or modify the user's music library.
- XCUITest now confirms two *imported file* decks, one independently playing deck, Hot Cue creation and paging via the real SwiftUI Menu.
- Native audio graph tests exercise AVAudioEngine offline rendering of A/B, EQ, Delay and looping. This is not a device hardware or signed release test.

## Remaining acceptance criteria

1. Run macOS GitHub Actions successfully including real Xcode full type-check + simulator audio graph + XCUITest.
2. Inspect generated screenshot against the first approved nine-page Canva concept.
3. Verify both decks and EQ, loop, file seek, Hot Cue and actual master WAV recording on iPhone.
4. Record route-change interruption, head/BT unplug, real-device touch performance and thermal results.
5. Sign and publish a TestFlight/IPA build via an account that owns an Apple development signing identity.

Do not label an unsigned simulator app or source ZIP a semi-release.
