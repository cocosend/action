#include "TrackAudioCore.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>

namespace {
void write16(std::ofstream &f, uint16_t value) {
  const unsigned char data[2] = {
      static_cast<unsigned char>(value),
      static_cast<unsigned char>(value >> 8)};
  f.write(reinterpret_cast<const char *>(data), 2);
}
void write32(std::ofstream &f, uint32_t value) {
  const unsigned char data[4] = {
      static_cast<unsigned char>(value), static_cast<unsigned char>(value >> 8),
      static_cast<unsigned char>(value >> 16), static_cast<unsigned char>(value >> 24)};
  f.write(reinterpret_cast<const char *>(data), 4);
}
void pcm(std::ofstream &out, float v) {
  const float peak = std::max(-1.0f, std::min(1.0f, v));
  write16(out, static_cast<uint16_t>(static_cast<int16_t>(std::round(peak * 32767.0f))));
}
} // namespace
int main(int argc, char **argv) {
  if (argc != 2) { std::cerr << "Usage: render_demo output.wav\n"; return 2; }
  constexpr uint32_t sampleRate = 48000;
  constexpr uint16_t channels = 2;
  constexpr uint32_t seconds = 12;
  constexpr uint32_t totalFrames = seconds * sampleRate;
  constexpr uint32_t dataBytes = totalFrames * channels * sizeof(int16_t);
  std::ofstream out(argv[1], std::ios::binary);
  if (!out) return 1;
  out.write("RIFF", 4); write32(out, 36 + dataBytes); out.write("WAVE", 4);
  out.write("fmt ", 4); write32(out, 16); write16(out, 1); write16(out, channels);
  write32(out, sampleRate); write32(out, sampleRate * channels * 2);
  write16(out, channels * 2); write16(out, 16);
  out.write("data", 4); write32(out, dataBytes);
  TBEngine *core = tb_create(sampleRate);
  if (!core) return 1;
  tb_set_playing(core, 1);
  tb_set_bpm(core, 138);
  tb_set_crossfader(core, 0.0f);
  tb_set_swing(core, 0.23f);
  tb_select_bank(core, 0, 1); // driving techno A
  tb_select_bank(core, 1, 3); // rolling acid groove B
  tb_set_deck_filter(core, 1, 0.82f);
  bool scheduled = false;
  std::vector<float> left(256), right(256);
  for (uint32_t offset = 0; offset < totalFrames;) {
    const uint32_t size = std::min<uint32_t>(256, totalFrames - offset);
    if (!scheduled && offset >= sampleRate * 3) {
      // Queue at 3 s, begin on the next 4/4 bar, transition over two bars.
      tb_schedule_pattern_automix(core, 1, 2);
      scheduled = true;
    }
    tb_render(core, left.data(), right.data(), size);
    for (uint32_t i = 0; i < size; ++i) {
      pcm(out, left[i]);
      pcm(out, right[i]);
    }
    offset += size;
  }
  tb_destroy(core);
  if (!out) return 1;
  std::cout << "Exported generated 12-second stereo WAV with 2-bar pattern AutoMix: " << argv[1] << '\n';
}
