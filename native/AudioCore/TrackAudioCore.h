#ifndef TRACK_AUDIO_CORE_H
#define TRACK_AUDIO_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TBEngine TBEngine;

enum TBInstrument {
  TBInstrumentKick = 0,
  TBInstrumentHat = 1,
  TBInstrumentBass = 2
};

// 2 decks, 4 banks/deck, 16 steps/bank and 3 voices/step.
// Engine lifetime: create/destroy ONLY while the audio callback is stopped.
TBEngine *tb_create(double sample_rate);
void tb_destroy(TBEngine *engine);

// Atomic, nonblocking control operations. Nonfinite controls are rejected.
void tb_set_playing(TBEngine *engine, int playing);
void tb_set_bpm(TBEngine *engine, double bpm); // 60..200
void tb_set_swing(TBEngine *engine, float swing); // 0..0.75, 16th-note pair timing
void tb_set_crossfader(TBEngine *engine, float position); // 0 A, 1 B
void tb_set_master_gain(TBEngine *engine, float gain); // 0..1
void tb_set_deck_gain(TBEngine *engine, int deck, float gain); // 0..1
void tb_set_deck_filter(TBEngine *engine, int deck, float openness); // 0..1, low-pass
// Per-deck pattern synth gate. An imported audio file can replace one deck's
// synthesized pattern while the other deck remains active. This does NOT mute
// the external AVAudioPlayerNode, which is managed by the iOS audio graph.
void tb_set_deck_enabled(TBEngine *engine, int deck, int enabled);
int tb_deck_enabled(const TBEngine *engine, int deck);
// Original synthesized voices ONLY (Kick/Hat/Bass). Not extracted file STEMS.
// Setters are atomic and render uses per-voice smoothing. Solo overrides mute.
void tb_set_pattern_voice_mute(TBEngine *engine, int deck, int voice, int muted);
void tb_set_pattern_voice_solo(TBEngine *engine, int deck, int voice, int solo);
int tb_pattern_voice_muted(const TBEngine *engine, int deck, int voice);
int tb_pattern_voice_soloed(const TBEngine *engine, int deck, int voice);
// Three-band equalizer -12..+12 dB per band: 0 LOW, 1 MID, 2 HIGH.
void tb_set_deck_eq(TBEngine *engine, int deck, int band, float db);
float tb_get_deck_eq(const TBEngine *engine, int deck, int band);
// Per-deck lightweight delay wet ratio 0..0.5, one fixed 3/8-second tap.
// Echo feedback is bounded; no dynamic allocation or locks in render.
void tb_set_deck_delay(TBEngine *engine, int deck, float wet);
float tb_get_deck_delay(const TBEngine *engine, int deck);
// Position within the 16-step pattern bar, 0..<1. Read-only UI timing.
float tb_bar_progress(const TBEngine *engine);

// A requested bank becomes audible at the beginning of the next bar.
// If playback is newly started/reset, the next bar begins immediately.
void tb_select_bank(TBEngine *engine, int deck, int bank); // 0..3
int tb_requested_bank(const TBEngine *engine, int deck);
int tb_active_bank(const TBEngine *engine, int deck);

void tb_set_step_bank(TBEngine *engine, int deck, int bank,
                      int instrument, int step, int enabled);
int tb_get_step_bank(const TBEngine *engine, int deck, int bank,
                     int instrument, int step);
void tb_set_velocity_bank(TBEngine *engine, int deck, int bank,
                          int instrument, int step, int velocity); // 0..127; 0=off
int tb_get_velocity_bank(const TBEngine *engine, int deck, int bank,
                         int instrument, int step);

// Legacy M0 wrappers address bank 0. New UI should use the bank-aware API.
void tb_set_step(TBEngine *engine, int deck, int instrument, int step, int enabled);
int tb_get_step(const TBEngine *engine, int deck, int instrument, int step);

// Pattern-only AutoMix prototype: schedule an equal-power crossfade at next
// bar downbeat, lasting 1..8 bars. This is NOT file BPM/beatgrid AutoMix.
// Manual tb_set_crossfader() cancels an in-flight AutoMix at the next block.
void tb_schedule_pattern_automix(TBEngine *engine, int target_deck, int bars);
void tb_cancel_pattern_automix(TBEngine *engine);
int tb_automix_state(const TBEngine *engine); // 0 idle, 1 queued, 2 fading
float tb_effective_crossfader(const TBEngine *engine); // 0..1

// Live drum/synth pad triggers are consumed at the next callback boundary.
// The transport must be playing for pad audio to be heard.
void tb_trigger_pad(TBEngine *engine, int deck, int instrument);
int tb_current_step(const TBEngine *engine);
void tb_request_reset(TBEngine *engine);

// Stereo, noninterleaved float32; bounded, lock-free, allocation-free DSP.
// A single audio thread may call tb_render. Control-thread setters are safe
// concurrently with that call. Do not destroy the engine while rendering.
void tb_render(TBEngine *engine, float *left, float *right, size_t frames);

#ifdef __cplusplus
}
#endif
#endif
