#include "TrackAudioCore.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <vector>
#include <new>

static_assert(std::atomic<float>::is_always_lock_free,
              "Real-time float controls must be lock-free");
static_assert(std::atomic<double>::is_always_lock_free,
              "Real-time double controls must be lock-free");
static_assert(std::atomic<uint8_t>::is_always_lock_free,
              "Per-step velocity controls must be lock-free");
static_assert(std::atomic<int>::is_always_lock_free,
              "Bank selection and step counters must be lock-free");

namespace {
constexpr double pi = 3.14159265358979323846;
constexpr int stepsPerBar = 16;
constexpr int voicesPerDeck = 3;
constexpr int numberOfDecks = 2;
constexpr int bankCount = 4;
constexpr float kickDecay = 0.9993f;
constexpr float hatDecay = 0.9925f;
constexpr float bassDecay = 0.99965f;

float clamp(float value, float low, float high) {
  return std::max(low, std::min(high, value));
}

double clampTempo(double bpm) {
  if (!std::isfinite(bpm)) return 132.0;
  return std::max(60.0, std::min(200.0, bpm));
}

bool validStep(int deck, int bank, int instrument, int step) {
  return deck >= 0 && deck < numberOfDecks && bank >= 0 && bank < bankCount &&
         instrument >= 0 && instrument < voicesPerDeck &&
         step >= 0 && step < stepsPerBar;
}

// Render-thread-owned biquads; coefficients are updated once per callback.
// RBJ Audio EQ Cookbook forms, normalized by a0. No dynamic allocation.
struct Biquad {
  float b0=1, b1=0, b2=0, a1=0, a2=0;
  float z1=0, z2=0;
  float process(float x) {
    const float y = b0 * x + z1;
    z1 = b1 * x - a1 * y + z2;
    z2 = b2 * x - a2 * y;
    return y;
  }
  void set(int band, double sr, float db) {
    const double f = std::min(band == 0 ? 180.0 : (band == 1 ? 1000.0 : 6200.0),
                              0.40 * sr); // Always below Nyquist even at 8 kHz.
    const double A = std::pow(10.0, double(db) / 40.0);
    const double w = 2.0 * pi * f / sr;
    const double co = std::cos(w), sn = std::sin(w);
    const double alpha = sn * 0.7071067811865476; // shelf slope = 1, mid Q approx 0.707
    const double rootA = std::sqrt(A);
    double n0,n1,n2,d0,d1,d2;
    if (band == 1) { // Peak 1 kHz
      n0 = 1 + alpha * A;
      n1 = -2 * co;
      n2 = 1 - alpha * A;
      d0 = 1 + alpha / A;
      d1 = -2 * co;
      d2 = 1 - alpha / A;
    } else if (band == 0) { // Low shelf
      n0 = A*((A+1)-(A-1)*co+2*rootA*alpha);
      n1 = 2*A*((A-1)-(A+1)*co);
      n2 = A*((A+1)-(A-1)*co-2*rootA*alpha);
      d0 = (A+1)+(A-1)*co+2*rootA*alpha;
      d1 = -2*((A-1)+(A+1)*co);
      d2 = (A+1)+(A-1)*co-2*rootA*alpha;
    } else { // High shelf
      n0 = A*((A+1)+(A-1)*co+2*rootA*alpha);
      n1 = -2*A*((A-1)+(A+1)*co);
      n2 = A*((A+1)+(A-1)*co-2*rootA*alpha);
      d0 = (A+1)-(A-1)*co+2*rootA*alpha;
      d1 = 2*((A-1)-(A+1)*co);
      d2 = (A+1)-(A-1)*co-2*rootA*alpha;
    }
    b0=float(n0/d0);b1=float(n1/d0);b2=float(n2/d0);
    a1=float(d1/d0);a2=float(d2/d0);
  }
};

struct Voice {
  double kickPhase = 0.0;
  double bassPhase = 0.0;
  float kickEnvelope = 0.0f;
  float hatEnvelope = 0.0f;
  float bassEnvelope = 0.0f;
  float bassFilter = 0.0f;
  float bassFrequency = 55.0f;
  uint32_t rng = 0xDEADBEEF;
};

struct Pattern {
  std::atomic<uint8_t> velocity[stepsPerBar][voicesPerDeck];
  Pattern(int deckIndex, int bankIndex) {
    for (int step = 0; step < stepsPerBar; ++step) {
      // Four intentionally distinct original techno patterns per deck.
      const bool fourToFloor = bankIndex == 0 || bankIndex == 1;
      const bool kick = fourToFloor ? step % 4 == 0 :
                        bankIndex == 2 ? step % 8 == 0 :
                        (step % 4 == 0 || step == 14);
      const bool hat = bankIndex == 0 ? step % 4 == 2 :
                       bankIndex == 1 ? step % 2 == 0 :
                       bankIndex == 2 ? (step == 6 || step == 14) :
                       (step % 2 != 0);
      const bool bass = bankIndex == 0 ?
                        (deckIndex == 0 ? (step == 0 || step == 7 || step == 10)
                                        : (step == 0 || step == 3 || step == 11 || step == 14)) :
                        bankIndex == 1 ? (step % 4 == (deckIndex == 0 ? 3 : 1)) :
                        bankIndex == 2 ? (step == 0 || step == 8 || step == 11) :
                        (step == 2 || step == 6 || step == 10 || step == 15);
      velocity[step][0].store(kick ? 112 : 0, std::memory_order_relaxed);
      velocity[step][1].store(hat ? 90 : 0, std::memory_order_relaxed);
      velocity[step][2].store(bass ? 106 : 0, std::memory_order_relaxed);
    }
  }
};

struct Deck {
  Pattern patterns[bankCount];
  std::atomic<int> requestedBank{0};
  std::atomic<int> activeBank{0};
  std::atomic<float> gain{1.0f};
  std::atomic<float> filter{1.0f};
  std::atomic<float> delayWet{0.0f};
  std::atomic<uint8_t> padRequests{0};
  std::atomic<uint8_t> enabled{1};
  std::atomic<uint8_t> mutedVoices{0}; // 3 bits, controller write, render read
  std::atomic<uint8_t> soloVoices{0};
  float voiceLevel[3] = {1.0f, 1.0f, 1.0f}; // one render thread only
  std::atomic<float> eqDB[3]{};
  Biquad eq[3];
  float smoothedEqDB[3]{};
  Voice voice;
  // Render-thread-only state.
  float smoothedGain = 1.0f;
  float smoothedFilter = 1.0f;
  float filterMemory = 0.0f;
  std::vector<float> delayLine;
  size_t delayIndex = 0;
  float smoothedDelay = 0.0f;
  int renderingBank = 0;

  explicit Deck(int index) : patterns{Pattern(index, 0), Pattern(index, 1),
                                       Pattern(index, 2), Pattern(index, 3)} {
    voice.rng ^= (0x9E3779B9u * static_cast<uint32_t>(index + 1));
  }
  // Called before audio rendering begins, exclusively on the control thread.
  void initializeDelay(double sampleRate) {
    delayLine.assign(std::max<size_t>(1, static_cast<size_t>(sampleRate * 0.375)), 0.f);
    delayIndex = 0;
  }
};

void trigger(Deck &deck, int instrument, int step, uint8_t velocity) {
  const float strength = static_cast<float>(velocity) / 127.0f;
  if (velocity == 0) return;
  switch (instrument) {
  case TBInstrumentKick:
    deck.voice.kickEnvelope = strength;
    deck.voice.kickPhase = 0.0;
    break;
  case TBInstrumentHat:
    deck.voice.hatEnvelope = strength * 0.48f;
    break;
  case TBInstrumentBass:
    deck.voice.bassEnvelope = strength * 0.5f;
    deck.voice.bassFrequency = (step % 4 == 3 ? 65.406f : 55.0f);
    break;
  default: break;
  }
}

float sample(Deck &deck, double sampleRate) {
  Voice &v = deck.voice;
  float kick = 0.0f;
  if (v.kickEnvelope > 0.00005f) {
    const double frequency = 48.0 + 100.0 * v.kickEnvelope * v.kickEnvelope;
    v.kickPhase += 2.0 * pi * frequency / sampleRate;
    if (v.kickPhase >= 2.0 * pi) v.kickPhase -= 2.0 * pi;
    kick = static_cast<float>(std::sin(v.kickPhase)) * v.kickEnvelope * 0.52f;
    v.kickEnvelope *= kickDecay;
  }
  float hat = 0.0f;
  if (v.hatEnvelope > 0.00005f) {
    v.rng ^= v.rng << 13;
    v.rng ^= v.rng >> 17;
    v.rng ^= v.rng << 5;
    const float noise = static_cast<float>(v.rng & 0xffffu) * (1.0f / 32768.0f) - 1.0f;
    hat = noise * v.hatEnvelope * 0.25f;
    v.hatEnvelope *= hatDecay;
  }
  float bass = 0.0f;
  if (v.bassEnvelope > 0.00005f) {
    v.bassPhase += v.bassFrequency / sampleRate;
    if (v.bassPhase >= 1.0) v.bassPhase -= 1.0;
    const float saw = static_cast<float>(2.0 * v.bassPhase - 1.0);
    v.bassFilter += 0.16f * (saw - v.bassFilter);
    bass = v.bassFilter * v.bassEnvelope * 0.3f;
    v.bassEnvelope *= bassDecay;
  }
  const uint8_t muted = deck.mutedVoices.load(std::memory_order_relaxed);
  const uint8_t solo = deck.soloVoices.load(std::memory_order_relaxed);
  float* voices[3] = {&kick, &hat, &bass};
  for (int i = 0; i < 3; ++i) {
    const uint8_t mask = uint8_t(1u << i);
    const bool audible = solo ? (solo & mask) != 0 : (muted & mask) == 0;
    // ~7 ms transition at 48kHz; no hard mute clicks on hot surfaces.
    deck.voiceLevel[i] += (float(audible) - deck.voiceLevel[i]) * 0.003f;
    *voices[i] *= deck.voiceLevel[i];
  }
  // Smooth control changes before the per-deck low-pass, not on the main thread.
  deck.smoothedGain += (deck.gain.load(std::memory_order_relaxed) - deck.smoothedGain) * 0.0015f;
  deck.smoothedFilter += (deck.filter.load(std::memory_order_relaxed) - deck.smoothedFilter) * 0.0015f;
  const float cutoff = deck.smoothedFilter;
  const float alpha = 0.004f + 0.996f * cutoff * cutoff;
  deck.filterMemory += alpha * (kick + hat + bass - deck.filterMemory);
  float output = deck.filterMemory * deck.smoothedGain;
  for (auto &filter : deck.eq) output = filter.process(output);
  if (!deck.delayLine.empty()) {
    const float tap = deck.delayLine[deck.delayIndex];
    deck.delayLine[deck.delayIndex] = clamp(output + tap * 0.28f, -2.0f, 2.0f);
    if (++deck.delayIndex >= deck.delayLine.size()) deck.delayIndex = 0;
    deck.smoothedDelay += (deck.delayWet.load(std::memory_order_relaxed) -
                           deck.smoothedDelay) * 0.0015f;
    output = (1.0f - deck.smoothedDelay) * output + deck.smoothedDelay * tap;
  }
  return output;
}

float softBound(float x) {
  const float compressed = x / (1.0f + 0.35f * std::fabs(x));
  return clamp(compressed, -0.98f, 0.98f);
}
} // namespace

struct TBEngine {
  const double sampleRate;
  std::atomic<bool> playing{false};
  std::atomic<bool> resetRequested{false};
  std::atomic<double> tempo{132.0};
  std::atomic<float> swing{0.0f};
  std::atomic<float> crossfader{0.5f};
  std::atomic<float> masterGain{0.7f};
  std::atomic<int> displayedStep{0};
  std::atomic<float> progress{0.0f};
  std::atomic<int> automixCommand{0}; // -1: cancel; 1..8: A; 9..16: B
  std::atomic<int> automixState{0};   // owned by render, read by UI
  std::atomic<float> effectiveCrossfader{0.5f};
  Deck deck[numberOfDecks] = {Deck(0), Deck(1)};
  // The following fields are exclusively used by the one render thread:
  double samplesIntoStep = 0.0;
  int nextStep = 0;
  int currentStep = 0;
  bool triggerNextStep = true;
  float smoothCrossfader = 0.5f;
  float smoothGain = 0.7f;
  int automixTarget = 1;
  int automixBars = 2;
  int automixCompletedSteps = 0;
  float automixStartXf = 0.5f;
  explicit TBEngine(double rate) : sampleRate(rate) {
    for (auto &d : deck) d.initializeDelay(rate);
  }
};

extern "C" {
TBEngine *tb_create(double sample_rate) {
  if (!std::isfinite(sample_rate) || sample_rate < 8000 || sample_rate > 192000)
    return nullptr;
  return new (std::nothrow) TBEngine(sample_rate);
}

void tb_destroy(TBEngine *engine) { delete engine; }

void tb_set_playing(TBEngine *engine, int playing) {
  if (engine) engine->playing.store(playing != 0, std::memory_order_release);
}

void tb_set_bpm(TBEngine *engine, double bpm) {
  if (engine) engine->tempo.store(clampTempo(bpm), std::memory_order_relaxed);
}

void tb_set_swing(TBEngine *engine, float swing) {
  if (engine && std::isfinite(swing))
    engine->swing.store(clamp(swing, 0.0f, 0.75f), std::memory_order_relaxed);
}

void tb_set_crossfader(TBEngine *engine, float position) {
  if (engine && std::isfinite(position))
  {
    engine->crossfader.store(clamp(position, 0.0f, 1.0f), std::memory_order_relaxed);
    engine->automixCommand.store(-1, std::memory_order_release);
  }
}

void tb_set_master_gain(TBEngine *engine, float gain) {
  if (engine && std::isfinite(gain))
    engine->masterGain.store(clamp(gain, 0.0f, 1.0f), std::memory_order_relaxed);
}

void tb_set_deck_gain(TBEngine *engine, int deck, float gain) {
  if (engine && deck >= 0 && deck < numberOfDecks && std::isfinite(gain))
    engine->deck[deck].gain.store(clamp(gain, 0.0f, 1.0f), std::memory_order_relaxed);
}

void tb_set_deck_filter(TBEngine *engine, int deck, float openness) {
  if (engine && deck >= 0 && deck < numberOfDecks && std::isfinite(openness))
    engine->deck[deck].filter.store(clamp(openness, 0.0f, 1.0f), std::memory_order_relaxed);
}

void tb_set_deck_enabled(TBEngine *engine, int deck, int enabled) {
  if (engine && deck >= 0 && deck < numberOfDecks)
    engine->deck[deck].enabled.store(enabled != 0, std::memory_order_release);
}

int tb_deck_enabled(const TBEngine *engine, int deck) {
  return (engine && deck >= 0 && deck < numberOfDecks) ?
    engine->deck[deck].enabled.load(std::memory_order_acquire) : 0;
}

void tb_set_pattern_voice_mute(TBEngine *engine, int deck, int voice, int muted) {
  if (!engine || deck < 0 || deck >= numberOfDecks || voice < 0 || voice >= voicesPerDeck) return;
  const uint8_t bit = uint8_t(1u << voice);
  if (muted) engine->deck[deck].mutedVoices.fetch_or(bit, std::memory_order_release);
  else engine->deck[deck].mutedVoices.fetch_and(uint8_t(~bit), std::memory_order_release);
}
void tb_set_pattern_voice_solo(TBEngine *engine, int deck, int voice, int solo) {
  if (!engine || deck < 0 || deck >= numberOfDecks || voice < 0 || voice >= voicesPerDeck) return;
  const uint8_t bit = uint8_t(1u << voice);
  if (solo) engine->deck[deck].soloVoices.fetch_or(bit, std::memory_order_release);
  else engine->deck[deck].soloVoices.fetch_and(uint8_t(~bit), std::memory_order_release);
}
int tb_pattern_voice_muted(const TBEngine *engine, int deck, int voice) {
  if (!engine || deck < 0 || deck >= numberOfDecks || voice < 0 || voice >= voicesPerDeck) return 0;
  return (engine->deck[deck].mutedVoices.load(std::memory_order_acquire) & (1u << voice)) != 0;
}
int tb_pattern_voice_soloed(const TBEngine *engine, int deck, int voice) {
  if (!engine || deck < 0 || deck >= numberOfDecks || voice < 0 || voice >= voicesPerDeck) return 0;
  return (engine->deck[deck].soloVoices.load(std::memory_order_acquire) & (1u << voice)) != 0;
}

void tb_set_deck_delay(TBEngine *engine, int deck, float wet) {
  if (!engine || deck < 0 || deck >= numberOfDecks || !std::isfinite(wet)) return;
  engine->deck[deck].delayWet.store(clamp(wet, 0.0f, 0.5f), std::memory_order_relaxed);
}
float tb_get_deck_delay(const TBEngine *engine, int deck) {
  if (!engine || deck < 0 || deck >= numberOfDecks) return 0.f;
  return engine->deck[deck].delayWet.load(std::memory_order_relaxed);
}

void tb_set_deck_eq(TBEngine *engine, int deck, int band, float db) {
  if (engine && deck >= 0 && deck < numberOfDecks && band >= 0 && band < 3 && std::isfinite(db))
    engine->deck[deck].eqDB[band].store(clamp(db, -12.0f, 12.0f), std::memory_order_release);
}

float tb_get_deck_eq(const TBEngine *engine, int deck, int band) {
  if (engine && deck >= 0 && deck < numberOfDecks && band >= 0 && band < 3)
    return engine->deck[deck].eqDB[band].load(std::memory_order_acquire);
  return 0.0f;
}

float tb_bar_progress(const TBEngine *engine) {
  return engine ? engine->progress.load(std::memory_order_relaxed) : 0.0f;
}

void tb_select_bank(TBEngine *engine, int deck, int bank) {
  if (engine && deck >= 0 && deck < numberOfDecks && bank >= 0 && bank < bankCount)
    engine->deck[deck].requestedBank.store(bank, std::memory_order_release);
}

int tb_requested_bank(const TBEngine *engine, int deck) {
  return (engine && deck >= 0 && deck < numberOfDecks) ?
      engine->deck[deck].requestedBank.load(std::memory_order_acquire) : -1;
}

int tb_active_bank(const TBEngine *engine, int deck) {
  return (engine && deck >= 0 && deck < numberOfDecks) ?
      engine->deck[deck].activeBank.load(std::memory_order_acquire) : -1;
}

void tb_set_velocity_bank(TBEngine *engine, int deck, int bank,
                          int instrument, int step, int velocity) {
  if (!engine || !validStep(deck, bank, instrument, step)) return;
  engine->deck[deck].patterns[bank].velocity[step][instrument].store(
      static_cast<uint8_t>(std::max(0, std::min(127, velocity))), std::memory_order_release);
}

int tb_get_velocity_bank(const TBEngine *engine, int deck, int bank,
                         int instrument, int step) {
  if (!engine || !validStep(deck, bank, instrument, step)) return 0;
  return engine->deck[deck].patterns[bank].velocity[step][instrument].load(
      std::memory_order_acquire);
}

void tb_set_step_bank(TBEngine *engine, int deck, int bank,
                      int instrument, int step, int enabled) {
  tb_set_velocity_bank(engine, deck, bank, instrument, step, enabled ? 110 : 0);
}

int tb_get_step_bank(const TBEngine *engine, int deck, int bank,
                     int instrument, int step) {
  return tb_get_velocity_bank(engine, deck, bank, instrument, step) > 0;
}

void tb_set_step(TBEngine *engine, int deck, int instrument, int step, int enabled) {
  tb_set_step_bank(engine, deck, 0, instrument, step, enabled);
}

int tb_get_step(const TBEngine *engine, int deck, int instrument, int step) {
  return tb_get_step_bank(engine, deck, 0, instrument, step);
}

void tb_schedule_pattern_automix(TBEngine *engine, int target_deck, int bars) {
  if (!engine || target_deck < 0 || target_deck >= numberOfDecks ||
      bars < 1 || bars > 8) return;
  const int command = bars + (target_deck == 1 ? 8 : 0);
  engine->automixCommand.store(command, std::memory_order_release);
}

void tb_cancel_pattern_automix(TBEngine *engine) {
  if (!engine) return;
  // Preserve the current audible position instead of snapping back to the
  // crossfader value from before the automated transition.
  engine->crossfader.store(engine->effectiveCrossfader.load(std::memory_order_relaxed),
                           std::memory_order_relaxed);
  engine->automixCommand.store(-1, std::memory_order_release);
}

int tb_automix_state(const TBEngine *engine) {
  return engine ? engine->automixState.load(std::memory_order_acquire) : 0;
}

float tb_effective_crossfader(const TBEngine *engine) {
  return engine ? engine->effectiveCrossfader.load(std::memory_order_relaxed) : 0.5f;
}

void tb_trigger_pad(TBEngine *engine, int deck, int instrument) {
  if (!engine || deck < 0 || deck >= numberOfDecks ||
      instrument < 0 || instrument >= voicesPerDeck) return;
  engine->deck[deck].padRequests.fetch_or(static_cast<uint8_t>(1u << instrument),
                                          std::memory_order_release);
}

int tb_current_step(const TBEngine *engine) {
  return engine ? engine->displayedStep.load(std::memory_order_relaxed) : 0;
}

void tb_request_reset(TBEngine *engine) {
  if (engine) engine->resetRequested.store(true, std::memory_order_release);
}

void tb_render(TBEngine *engine, float *left, float *right, size_t frames) {
  if (!left || !right) return;
  if (!engine) {
    for (size_t i = 0; i < frames; ++i) left[i] = right[i] = 0.0f;
    return;
  }
  // Process an entire command once per callback, never from the UI thread.
  const int mixCommand = engine->automixCommand.exchange(0, std::memory_order_acq_rel);
  if (mixCommand == -1) {
    engine->automixState.store(0, std::memory_order_release);
  } else if (mixCommand > 0) {
    engine->automixTarget = mixCommand > 8 ? 1 : 0;
    engine->automixBars = mixCommand > 8 ? mixCommand - 8 : mixCommand;
    engine->automixState.store(1, std::memory_order_release);
  }
  if (engine->resetRequested.exchange(false, std::memory_order_acquire)) {
    engine->automixState.store(0, std::memory_order_release);
    engine->nextStep = 0;
    engine->currentStep = 0;
    engine->samplesIntoStep = 0.0;
    engine->triggerNextStep = true;
    engine->displayedStep.store(0, std::memory_order_relaxed);
    engine->progress.store(0.0f, std::memory_order_relaxed);
    for (auto &deck : engine->deck) {
      deck.voice = Voice{};
      deck.filterMemory = 0.0f;
      deck.padRequests.store(0, std::memory_order_relaxed);
    }
  }
  if (!engine->playing.load(std::memory_order_acquire)) {
    for (size_t i = 0; i < frames; ++i) left[i] = right[i] = 0.0f;
    return;
  }
  // Smooth three EQ bands at buffer boundaries; no coefficient math per sample.
  for (auto &deck : engine->deck) {
    for (int band = 0; band < 3; ++band) {
      const float target = deck.eqDB[band].load(std::memory_order_relaxed);
      const float before = deck.smoothedEqDB[band];
      const float next = before + (target - before) * 0.14f;
      if (std::fabs(next - before) > 0.00001f) {
        deck.eq[band].set(band, engine->sampleRate, next);
        deck.smoothedEqDB[band] = next;
      }
    }
  }
  // Pads incur at most one buffer's scheduling latency. This avoids work in UI callbacks.
  for (auto &deck : engine->deck) {
    const uint8_t pads = deck.padRequests.exchange(0, std::memory_order_acquire);
    for (int voice = 0; voice < voicesPerDeck; ++voice)
      if (pads & (1u << voice)) trigger(deck, voice, engine->currentStep, 127);
  }
  for (size_t i = 0; i < frames; ++i) {
    const double bpm = engine->tempo.load(std::memory_order_relaxed);
    const float swing = engine->swing.load(std::memory_order_relaxed);
    if (engine->triggerNextStep) {
      engine->triggerNextStep = false;
      engine->currentStep = engine->nextStep;
      const int mixState = engine->automixState.load(std::memory_order_relaxed);
      if (mixState == 1 && engine->currentStep == 0) {
        engine->automixStartXf = engine->smoothCrossfader;
        engine->automixCompletedSteps = 0;
        engine->automixState.store(2, std::memory_order_release);
      } else if (mixState == 2) {
        ++engine->automixCompletedSteps;
        if (engine->automixCompletedSteps >= engine->automixBars * stepsPerBar) {
          engine->automixState.store(0, std::memory_order_release);
          engine->crossfader.store(float(engine->automixTarget), std::memory_order_relaxed);
        }
      }
      for (auto &deck : engine->deck) {
        if (engine->currentStep == 0) {
          deck.renderingBank = deck.requestedBank.load(std::memory_order_acquire);
          deck.activeBank.store(deck.renderingBank, std::memory_order_release);
        }
        if (!deck.enabled.load(std::memory_order_acquire)) continue;
        const Pattern &pattern = deck.patterns[deck.renderingBank];
        for (int voice = 0; voice < voicesPerDeck; ++voice) {
          const uint8_t velocity = pattern.velocity[engine->currentStep][voice].load(
              std::memory_order_acquire);
          trigger(deck, voice, engine->currentStep, velocity);
        }
      }
      engine->displayedStep.store(engine->currentStep, std::memory_order_relaxed);
      engine->nextStep = (engine->nextStep + 1) % stepsPerBar;
    }
    // Paired 16th notes retain exactly two nominal steps of elapsed time.
    const double stepLength = engine->sampleRate * 15.0 / bpm *
        (1.0 + ((engine->currentStep & 1) ? -0.5 : 0.5) * swing);
    // Keep rendering an inactive voice's decay (no retrigger), but hard-gate
    // its output. This avoids a stale voice reappearing if synth/file mode
    // changes. The gate itself remains atomic and audio-thread nonblocking.
    const bool enabledA = engine->deck[0].enabled.load(std::memory_order_acquire) != 0;
    const bool enabledB = engine->deck[1].enabled.load(std::memory_order_acquire) != 0;
    const float aSample = sample(engine->deck[0], engine->sampleRate);
    const float bSample = sample(engine->deck[1], engine->sampleRate);
    const float a = enabledA ? aSample : 0.0f;
    const float b = enabledB ? bSample : 0.0f;
    float targetXf = engine->crossfader.load(std::memory_order_relaxed);
    if (engine->automixState.load(std::memory_order_relaxed) == 2) {
      const double stepFraction = clamp(float(engine->samplesIntoStep / stepLength), 0.0f, 1.0f);
      const float fraction = clamp(float((engine->automixCompletedSteps + stepFraction) /
                                         (engine->automixBars * stepsPerBar)), 0.0f, 1.0f);
      const float curve = fraction * fraction * (3.0f - 2.0f * fraction);
      targetXf = engine->automixStartXf +
                 (float(engine->automixTarget) - engine->automixStartXf) * curve;
    }
    engine->smoothCrossfader += (targetXf - engine->smoothCrossfader) * 0.002f;
    engine->effectiveCrossfader.store(engine->smoothCrossfader, std::memory_order_relaxed);
    engine->smoothGain +=
        (engine->masterGain.load(std::memory_order_relaxed) - engine->smoothGain) * 0.002f;
    const float aa = std::sqrt(1.0f - engine->smoothCrossfader) * engine->smoothGain;
    const float bb = std::sqrt(engine->smoothCrossfader) * engine->smoothGain;
    // Slight complementary stereo spread while remaining mono-compatible.
    left[i]  = softBound(a * aa + b * bb * 0.78f);
    right[i] = softBound(a * aa * 0.78f + b * bb);
    engine->samplesIntoStep += 1.0;
    if (engine->samplesIntoStep >= stepLength) {
      engine->samplesIntoStep -= stepLength;
      engine->triggerNextStep = true;
    }
  }
  const float position = clamp(float((engine->currentStep +
      (engine->triggerNextStep ? 1.0 : engine->samplesIntoStep /
       (engine->sampleRate * 15.0 / engine->tempo.load(std::memory_order_relaxed)))) / 16.0),
       0.0f, 1.0f);
  engine->progress.store(position >= 1.0f ? 0.0f : position, std::memory_order_relaxed);
}
} // extern "C"
