#include "TrackAudioCore.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <thread>
#include <vector>

#define CHECK(expr) do { if (!(expr)) { \
  std::cerr << "FAIL " << #expr << " at " << __FILE__ << ':' << __LINE__ << '\n'; \
  std::abort(); } } while (false)

namespace {
constexpr size_t sampleRate = 48000;

void silencePattern(TBEngine *engine, int deck, int bank) {
  for (int i = 0; i < 16; ++i)
    for (int voice = 0; voice < 3; ++voice)
      tb_set_velocity_bank(engine, deck, bank, voice, i, 0);
}

struct Levels {
  double rms = 0.0;
  double highFrequency = 0.0;
  float peak = 0.0f;
  bool stereo = false;
};

Levels analyze(TBEngine *engine, size_t frames, size_t block = 256) {
  std::vector<float> left(block), right(block);
  Levels result;
  double energy = 0.0;
  float previous = 0.0f;
  for (size_t done = 0; done < frames;) {
    const size_t count = std::min(block, frames - done);
    tb_render(engine, left.data(), right.data(), count);
    for (size_t i = 0; i < count; ++i) {
      const float x = left[i], y = right[i];
      CHECK(std::isfinite(x) && std::isfinite(y));
      CHECK(std::abs(x) <= 0.981f && std::abs(y) <= 0.981f);
      energy += double(x) * x;
      result.highFrequency += std::abs(x - previous);
      previous = x;
      result.peak = std::max(result.peak, std::max(std::abs(x), std::abs(y)));
      result.stereo |= (x != y);
    }
    done += count;
  }
  result.rms = std::sqrt(energy / static_cast<double>(frames));
  return result;
}

void checkSwingTiming() {
  TBEngine *core = tb_create(sampleRate);
  CHECK(core != nullptr);
  tb_set_bpm(core, 120.0);
  tb_set_swing(core, 0.5f);
  tb_set_playing(core, 1);
  std::vector<float> left(7500), right(7500);
  tb_render(core, left.data(), right.data(), 7500);
  CHECK(tb_current_step(core) == 0); // 6000 * 1.25 frames
  tb_render(core, left.data(), right.data(), 1);
  CHECK(tb_current_step(core) == 1);
  tb_render(core, left.data(), right.data(), 4499);
  CHECK(tb_current_step(core) == 1); // shorter adjacent step: 6000 * 0.75
  tb_render(core, left.data(), right.data(), 1);
  CHECK(tb_current_step(core) == 2); // same total duration as unswung pair
  tb_destroy(core);
}

void checkBanksAndControls() {
  TBEngine *core = tb_create(sampleRate);
  CHECK(core != nullptr);
  CHECK(tb_requested_bank(core, 0) == 0 && tb_active_bank(core, 0) == 0);
  CHECK(tb_get_step_bank(core, 0, 0, TBInstrumentKick, 0) == 1);
  CHECK(tb_get_step_bank(core, 0, 1, TBInstrumentHat, 4) == 1);
  CHECK(tb_get_step_bank(core, 0, 2, TBInstrumentKick, 4) == 0);
  tb_set_step_bank(core, 0, 2, TBInstrumentKick, 4, 1);
  CHECK(tb_get_velocity_bank(core, 0, 2, TBInstrumentKick, 4) == 110);
  tb_set_velocity_bank(core, 0, 2, TBInstrumentKick, 4, 21);
  CHECK(tb_get_velocity_bank(core, 0, 2, TBInstrumentKick, 4) == 21);
  tb_set_velocity_bank(core, 0, 2, TBInstrumentKick, 4, 500);
  CHECK(tb_get_velocity_bank(core, 0, 2, TBInstrumentKick, 4) == 127);
  tb_set_velocity_bank(core, 0, 2, TBInstrumentKick, 4, -5);
  CHECK(tb_get_step_bank(core, 0, 2, TBInstrumentKick, 4) == 0);
  tb_select_bank(core, 0, 9); // ignored
  CHECK(tb_requested_bank(core, 0) == 0);
  tb_select_bank(core, 0, 2);
  CHECK(tb_requested_bank(core, 0) == 2);
  CHECK(tb_active_bank(core, 0) == 0);
  tb_set_bpm(core, 120);
  tb_set_playing(core, 1);
  CHECK(analyze(core, 1).stereo == false); // first sample may be zero kick phase
  CHECK(tb_active_bank(core, 0) == 2); // immediately on first bar
  tb_select_bank(core, 0, 3);
  CHECK(tb_requested_bank(core, 0) == 3);
  CHECK(tb_active_bank(core, 0) == 2); // queued till step 0
  analyze(core, sampleRate);
  CHECK(tb_active_bank(core, 0) == 2); // 8 steps at 120 BPM
  analyze(core, sampleRate / 2);
  CHECK(tb_active_bank(core, 0) == 2); // 12 steps
  analyze(core, sampleRate / 2);
  CHECK(tb_active_bank(core, 0) == 3); // new bar
  tb_set_deck_gain(core, -1, 0);
  tb_set_deck_filter(core, -1, 0);
  tb_set_swing(core, NAN);
  CHECK(tb_active_bank(core, -1) == -1);
  tb_destroy(core);
}

void checkPadAndGain() {
  TBEngine *core = tb_create(sampleRate);
  for (int deck = 0; deck < 2; ++deck) silencePattern(core, deck, 0);
  tb_set_crossfader(core, 0);
  tb_set_playing(core, 1);
  CHECK(analyze(core, 4800).rms == 0);
  tb_trigger_pad(core, 0, TBInstrumentHat);
  CHECK(analyze(core, 2048).rms > 0.002);
  tb_request_reset(core);
  analyze(core, 4096);
  tb_trigger_pad(core, 0, 44); // ignored
  CHECK(analyze(core, 2048).rms == 0.0);
  tb_trigger_pad(core, 0, TBInstrumentBass);
  CHECK(analyze(core, 2048).rms > 0.0002);
  tb_set_deck_gain(core, 0, 0.0f);
  analyze(core, 20000); // control ramp and decaying previous bass
  CHECK(analyze(core, 48000).rms < 0.0002);
  tb_destroy(core);
}

void checkVelocityAndFilter() {
  auto makeCore = [](int velocity, float openness) {
    TBEngine *core = tb_create(sampleRate);
    for (int deck = 0; deck < 2; ++deck) silencePattern(core, deck, 0);
    tb_set_velocity_bank(core, 0, 0, TBInstrumentHat, 0, velocity);
    tb_set_crossfader(core, 0);
    tb_set_deck_filter(core, 0, openness);
    tb_set_playing(core, 1);
    return core;
  };
  TBEngine *loud = makeCore(127, 1);
  TBEngine *quiet = makeCore(25, 1);
  Levels a = analyze(loud, sampleRate);
  Levels b = analyze(quiet, sampleRate);
  CHECK(a.rms > b.rms * 3.0);
  CHECK(a.stereo);
  tb_destroy(loud);
  tb_destroy(quiet);
  TBEngine *open = makeCore(127, 1);
  TBEngine *closed = makeCore(127, 0);
  const Levels hi = analyze(open, sampleRate * 2);
  const Levels lo = analyze(closed, sampleRate * 2);
  CHECK(hi.highFrequency > lo.highFrequency * 2.0);
  tb_destroy(open);
  tb_destroy(closed);
}

void checkPatternAutoMix() {
  TBEngine *core = tb_create(sampleRate);
  tb_set_bpm(core, 120);
  tb_set_crossfader(core, 0.0f);
  tb_set_playing(core, 1);
  analyze(core, sampleRate); // 1s into the bar, crossfader has settled left.
  CHECK(tb_effective_crossfader(core) < 0.01f);
  tb_schedule_pattern_automix(core, 1, 2); // to deck B, 2 musical bars
  analyze(core, sampleRate / 4);
  CHECK(tb_automix_state(core) == 1); // quantized, still queued
  CHECK(tb_effective_crossfader(core) < 0.01f);
  analyze(core, sampleRate * 3 / 4);
  CHECK(tb_automix_state(core) == 1);
  analyze(core, 1);
  CHECK(tb_automix_state(core) == 2); // beginning of the next bar
  analyze(core, sampleRate * 2);
  CHECK(tb_automix_state(core) == 2);
  CHECK(tb_effective_crossfader(core) > 0.40f);
  CHECK(tb_effective_crossfader(core) < 0.60f);
  analyze(core, sampleRate * 2 + 1);
  CHECK(tb_automix_state(core) == 0);
  CHECK(tb_effective_crossfader(core) > 0.99f);
  tb_schedule_pattern_automix(core, 0, 1);
  analyze(core, 1);
  CHECK(tb_automix_state(core) == 1); // wait for next downbeat
  analyze(core, sampleRate * 2);
  CHECK(tb_automix_state(core) == 2); // reverse starts on downbeat
  analyze(core, sampleRate / 2);
  CHECK(tb_effective_crossfader(core) < 1.0f);
  tb_set_crossfader(core, 0.3f); // manual intervention must win
  analyze(core, 2048);
  CHECK(tb_automix_state(core) == 0);
  CHECK(std::abs(tb_effective_crossfader(core) - 0.3f) < 0.02f);
  tb_schedule_pattern_automix(core, 1, 1);
  tb_cancel_pattern_automix(core);
  analyze(core, 512);
  CHECK(tb_automix_state(core) == 0);
  tb_destroy(core);
}

void checkIndependentDeckGatesAndEQ() {
  TBEngine *core = tb_create(sampleRate);
  CHECK(core != nullptr);
  CHECK(tb_deck_enabled(core, 0) == 1);
  CHECK(tb_deck_enabled(core, 1) == 1);
  tb_set_crossfader(core, 0.0f);
  tb_set_playing(core, 1);
  CHECK(analyze(core, sampleRate / 2).rms > 0.003);
  CHECK(tb_bar_progress(core) > 0.20f && tb_bar_progress(core) < 0.31f);
  tb_set_deck_enabled(core, 0, 0);
  CHECK(tb_deck_enabled(core, 0) == 0);
  CHECK(analyze(core, 8192).rms < 0.000001);  // A gated, B nearly zero on xf
  tb_set_crossfader(core, 1.0f);
  CHECK(analyze(core, sampleRate / 2).rms > 0.001); // B remains audible
  tb_set_deck_enabled(core, 1, 0);
  CHECK(analyze(core, 8192).rms == 0.0);
  tb_set_deck_enabled(core, 0, 1);
  tb_set_crossfader(core, 0.0f);
  CHECK(analyze(core, sampleRate / 2).rms > 0.001);
  // EQ is per deck, finite, clamped and editable while playing.
  for (int band = 0; band < 3; ++band) {
    CHECK(tb_get_deck_eq(core, 0, band) == 0.0f);
    tb_set_deck_eq(core, 0, band, 100.0f);
    CHECK(tb_get_deck_eq(core, 0, band) == 12.0f);
    tb_set_deck_eq(core, 0, band, -100.0f);
    CHECK(tb_get_deck_eq(core, 0, band) == -12.0f);
    tb_set_deck_eq(core, 0, band, NAN);
    CHECK(tb_get_deck_eq(core, 0, band) == -12.0f);
  }
  CHECK(tb_get_deck_eq(core, -1, 0) == 0.0f);
  CHECK(tb_get_deck_eq(core, 1, 0) == 0.0f);
  Levels processed = analyze(core, sampleRate * 2);
  CHECK(processed.peak < 0.981f);
  CHECK(std::isfinite(processed.rms));
  tb_destroy(core);
}

void checkEQStableAcrossSupportedRates() {
  for (double rate : {8000.0, 16000.0, 44100.0, 48000.0, 96000.0, 192000.0}) {
    TBEngine *engine = tb_create(rate);
    CHECK(engine != nullptr);
    tb_set_playing(engine, 1);
    for (int band = 0; band < 3; ++band) {
      tb_set_deck_eq(engine, 0, band, 12);
      tb_set_deck_eq(engine, 1, band, -12);
    }
    const Levels result = analyze(engine, size_t(rate / 3));
    CHECK(std::isfinite(result.rms));
    CHECK(result.peak <= 0.981f);
    tb_destroy(engine);
  }
}

void checkEQAudibleChanges() {
  auto make = [](int voice, float low, float mid, float high) {
    TBEngine *core = tb_create(sampleRate);
    for (int d = 0; d < 2; ++d) silencePattern(core, d, 0);
    tb_set_velocity_bank(core, 0, 0, voice, 0, 127);
    tb_set_deck_eq(core, 0, 0, low);
    tb_set_deck_eq(core, 0, 1, mid);
    tb_set_deck_eq(core, 0, 2, high);
    tb_set_crossfader(core, 0);
    tb_set_playing(core, 1);
    return core;
  };
  TBEngine *hatFlat = make(TBInstrumentHat, 0, 0, 0);
  TBEngine *hatBoost = make(TBInstrumentHat, 0, 0, 12);
  const Levels flat = analyze(hatFlat, sampleRate / 2);
  const Levels boost = analyze(hatBoost, sampleRate / 2);
  CHECK(boost.rms > flat.rms * 1.08);
  tb_destroy(hatFlat);
  tb_destroy(hatBoost);
  TBEngine *bassFlat = make(TBInstrumentBass, 0, 0, 0);
  TBEngine *bassCut = make(TBInstrumentBass, -12, 0, 0);
  const Levels original = analyze(bassFlat, sampleRate / 2);
  const Levels cut = analyze(bassCut, sampleRate / 2);
  CHECK(original.rms > cut.rms * 1.3);
  tb_destroy(bassFlat);
  tb_destroy(bassCut);
}

void checkPerDeckDelay() {
  auto *flat = tb_create(sampleRate), *wet = tb_create(sampleRate);
  CHECK(flat != nullptr && wet != nullptr);
  tb_set_deck_enabled(flat, 1, 0);
  tb_set_deck_enabled(wet, 1, 0);
  tb_set_crossfader(flat, 0);
  tb_set_crossfader(wet, 0);
  tb_set_deck_delay(flat, 0, 0);
  tb_set_deck_delay(wet, 0, 0.4f);
  CHECK(tb_get_deck_delay(flat, 0) == 0);
  CHECK(tb_get_deck_delay(wet, 0) == 0.4f);
  tb_set_deck_delay(wet, 1, 1.0f);  // must clamp high feedback/wet
  CHECK(tb_get_deck_delay(wet, 1) == 0.5f);
  tb_set_deck_delay(wet, 0, NAN);  // invalid controls don't touch DSP
  CHECK(tb_get_deck_delay(wet, 0) == 0.4f);
  tb_set_playing(flat, 1);
  tb_set_playing(wet, 1);
  std::vector<float> al(256), ar(256), bl(256), br(256);
  double difference = 0.0, energy = 0.0;
  for (int i = 0; i < 2 * int(sampleRate / 256); ++i) {
    tb_render(flat, al.data(), ar.data(), 256);
    tb_render(wet, bl.data(), br.data(), 256);
    for (int j = 0; j < 256; ++j) {
      CHECK(std::isfinite(bl[j]) && std::abs(bl[j]) <= 0.98f);
      CHECK(std::isfinite(br[j]) && std::abs(br[j]) <= 0.98f);
      difference += std::abs(double(bl[j]) - double(al[j]));
      energy += double(bl[j]) * bl[j];
    }
  }
  CHECK(difference > 100.0);
  CHECK(energy > 10.0);
  tb_destroy(flat); tb_destroy(wet);
}

void checkRealtimeConcurrentControl() {
  TBEngine *core = tb_create(sampleRate);
  tb_set_playing(core, 1);
  std::atomic<bool> go{false};
  std::thread control([&] {
    while (!go.load(std::memory_order_acquire)) std::this_thread::yield();
    for (int i = 0; i < 20000; ++i) {
      tb_set_bpm(core, 80 + i % 100);
      tb_set_swing(core, (i % 75) * 0.01f);
      tb_select_bank(core, i % 2, i % 4);
      tb_set_deck_filter(core, i % 2, float(i % 100) / 100);
      tb_set_deck_gain(core, i % 2, float(i % 100) / 100);
      tb_set_deck_eq(core, i % 2, i % 3, float(i % 25) - 12.0f);
      tb_set_deck_delay(core, i % 2, float(i % 11) / 20);
      if (i % 31 == 0) tb_set_deck_enabled(core, i % 2, (i / 31) % 2);
      tb_set_velocity_bank(core, i % 2, i % 4, i % 3, i % 16, i % 128);
      if (i % 47 == 0) tb_trigger_pad(core, i % 2, i % 3);
    }
  });
  go.store(true, std::memory_order_release);
  analyze(core, 96000, 128);
  control.join();
  analyze(core, 9600);
  tb_destroy(core);
}
} // namespace

int main() {
  checkSwingTiming();
  checkBanksAndControls();
  checkPadAndGain();
  checkVelocityAndFilter();
  checkPatternAutoMix();
  checkIndependentDeckGatesAndEQ();
  checkEQAudibleChanges();
  checkEQStableAcrossSupportedRates();
  checkRealtimeConcurrentControl();
  checkPerDeckDelay();
  std::cout << "Advanced AudioCore: swing, banks, EQ, deck gates, pads, filter, automix, concurrency PASS\n";
}
