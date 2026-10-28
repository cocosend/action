#!/usr/bin/env bash
# Local verification for source-only iOS DJ prototype. Does NOT validate Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
work="${TMPDIR:-/tmp}/mixauto-verify-$$"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cmake -S . -B "$work/release" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$work/release" --parallel 4 >/dev/null
ctest --test-dir "$work/release" --output-on-failure
swiftc ios/App/TempoAnalyzer.swift tests/TempoAnalyzerTests.swift -o "$work/tempo"
"$work/tempo" >"$work/tempo.log"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift tests/BeatGridAnalyzerTests.swift -o "$work/beatgrid"
"$work/beatgrid" >"$work/beatgrid.log"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift ios/App/FileLoopPlan.swift ios/App/ImportedAudioStore.swift ios/App/BeatGridEditor.swift tests/BeatGridEditorTests.swift -o "$work/editor"
"$work/editor"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift ios/App/FileLoopPlan.swift ios/App/ImportedAudioStore.swift ios/App/FileDeckPerformance.swift tests/FileDeckPerformanceTests.swift -o "$work/cues"
"$work/cues"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift ios/App/FileLoopPlan.swift ios/App/ImportedAudioStore.swift ios/App/BeatGridEditor.swift ios/App/FileDeckPerformance.swift ios/App/AnalysisMergePolicy.swift tests/AnalysisMergePolicyTests.swift -o "$work/analysis_merge"
"$work/analysis_merge"
swiftc ios/App/TimedBlendPlan.swift tests/TimedBlendPlanTests.swift -o "$work/blend"
"$work/blend"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift ios/App/BeatHintTransition.swift tests/BeatHintTransitionTests.swift -o "$work/beat_hint"
"$work/beat_hint"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift ios/App/FileLoopPlan.swift tests/FileLoopPlanTests.swift -o "$work/loops"
"$work/loops"
swiftc ios/App/TempoAnalyzer.swift ios/App/TempoCompatibility.swift tests/TempoCompatibilityTests.swift -o "$work/compat"
"$work/compat"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift ios/App/TrackProject.swift ios/App/FileLoopPlan.swift ios/App/ImportedAudioStore.swift tests/TrackProjectTests.swift -o "$work/project"
"$work/project"
"$work/release/render_cockpit_demo" "$work/test.wav"
swiftc ios/App/TempoAnalyzer.swift ios/App/BeatGridAnalyzer.swift tests/TempoRealWavTests.swift -o "$work/realwav"
"$work/realwav" "$work/test.wav"
swiftc ios/App/AudioRoutePolicy.swift tests/AudioRoutePolicyTests.swift -o "$work/route_policy"
"$work/route_policy"
swiftc ios/App/BackgroundWork.swift tests/BackgroundWorkTests.swift -o "$work/background_work"
"$work/background_work"
swiftc ios/App/ImportCommitPolicy.swift tests/ImportCommitPolicyTests.swift -o "$work/import_policy"
"$work/import_policy"
swiftc -frontend -parse ios/App/*.swift ios/UITests/*.swift ios/IntegrationTests/*.swift
python3 - "$work/test.wav" <<'PY'
import sys,wave,struct,math
with wave.open(sys.argv[1], 'rb') as f:
    assert f.getnchannels()==2 and f.getsampwidth()==2 and f.getframerate()==48000
    rate=f.getframerate(); count=f.getnframes()
    assert count==rate*16
    frames=f.readframes(count)
    pcm=struct.unpack('<'+str(count*2)+'h',frames)
    rms=math.sqrt(sum(v*v for v in pcm[::40]) / len(pcm[::40])) / 32768
    peak=max(abs(v) for v in pcm)
    assert 0.01<rms<0.85 and peak<32767
    print('WAV stereo, 48 kHz, 16 s, peak=',peak,'RMS(sampled)=',round(rms,4))
PY
"$work/release/render_stem_demo" "$work/stems.wav"
python3 - "$work/stems.wav" <<'PY_STEMS'
import sys, wave, struct, math
with wave.open(sys.argv[1], 'rb') as f:
    assert (f.getframerate(), f.getnchannels(), f.getsampwidth(), f.getnframes()) == (48000, 2, 2, 16*48000)
    values = struct.unpack('<'+str(16*48000*2)+'h', f.readframes(16*48000))
    rms = []
    for section in range(4):
        samples = values[section*4*48000*2:(section+1)*4*48000*2]
        energy = math.sqrt(sum(v*v for v in samples[::32])/len(samples[::32]))/32768
        assert 0.0002 < energy < 0.9 and max(abs(v) for v in samples) < 32767
        rms.append(round(energy, 5))
    assert rms[2] < rms[0]*0.30, 'Solo hats must reduce output energy'
    print('Original synth voice mute/solo WAV PASS; RMS per 4s:', rms)
PY_STEMS
python3 tests/test_package_source.py
if [[ "${MIXAUTO_SKIP_SANITIZERS:-0}" != "1" ]] && command -v clang++ >/dev/null 2>&1; then
  cmake -S . -B "$work/sanitized" -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_CXX_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' \
    -DCMAKE_EXE_LINKER_FLAGS='-fsanitize=address,undefined' >/dev/null
  cmake --build "$work/sanitized" --target track_audio_core_tests advanced_audio_core_tests spectral_envelope_tests pattern_stem_controls_tests master_capture_ring_tests --parallel 1 >/dev/null
  ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 \
    ctest --test-dir "$work/sanitized" --output-on-failure
fi
python3 scripts/package_source.py "$work/source-checkpoint.zip" >/dev/null
python3 - "$work/source-checkpoint.zip" <<'PY_PACKAGE'
from zipfile import ZipFile
import hashlib,sys
with ZipFile(sys.argv[1]) as z:
    assert z.testzip() is None
    names=z.namelist()
    assert not any('/.build' in name for name in names)
    must_have=['ios/App/AudioRoutePolicy.swift','ios/App/BackgroundWork.swift',
               'ios/UITests/DJTrackBuilderUITests.swift','ios/IntegrationTests/AudioGraphIntegrationTests.swift',
               'tests/AudioRoutePolicyTests.swift','tests/BackgroundWorkTests.swift']
    for key in must_have:
        assert any(name.endswith(key) for name in names), key
    lines=z.read('DJ-TrackBuilder-MixAuto-Pro/SOURCE_SHA256SUMS.txt').decode().splitlines()
    for line in lines:
        digest,rel=line.split('  ',1)
        assert hashlib.sha256(z.read('DJ-TrackBuilder-MixAuto-Pro/'+rel)).hexdigest()==digest,rel
    print('Source ZIP manifest, cancellation/route sources and build-dir exclusions PASS')
PY_PACKAGE
echo 'SOURCE-ONLY VERIFICATION PASS (not Apple SDK, simulator, nor iPhone audio QA)'
