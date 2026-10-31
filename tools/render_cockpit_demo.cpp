#include "TrackAudioCore.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <vector>

namespace {
void u16(std::ofstream &f, uint16_t v) { const char b[2]={char(v),char(v>>8)}; f.write(b,2); }
void u32(std::ofstream &f, uint32_t v) { const char b[4]={char(v),char(v>>8),char(v>>16),char(v>>24)}; f.write(b,4); }
}
int main(int argc, char **argv) {
  if (argc != 2) { std::cerr << "Usage: render_cockpit_demo out.wav\n"; return 2; }
  constexpr uint32_t sr=48000, frames=sr*16, bytes=frames*2*2;
  std::ofstream out(argv[1],std::ios::binary);
  if (!out) return 1;
  out.write("RIFF",4);u32(out,36+bytes);out.write("WAVE",4);
  out.write("fmt ",4);u32(out,16);u16(out,1);u16(out,2);
  u32(out,sr);u32(out,sr*4);u16(out,4);u16(out,16);
  out.write("data",4);u32(out,bytes);
  auto *core=tb_create(sr);
  if (!core) return 1;
  tb_set_bpm(core,138);
  tb_set_swing(core,0.15f);
  tb_select_bank(core,0,1);
  tb_select_bank(core,1,3);
  tb_set_crossfader(core,0.0f);
  tb_set_deck_enabled(core,1,0);
  tb_set_playing(core,1);
  bool bOn=false, cross=false, autoBack=false;
  std::vector<float> left(256),right(256);
  for(uint32_t at=0;at<frames;) {
    if(!bOn && at>=sr*4) {
      tb_set_deck_enabled(core,1,1);
      tb_set_deck_eq(core,1,2,5); // bright high shelf on deck B
      tb_set_crossfader(core,0.5f);
      bOn=true;
    }
    if(!cross && at>=sr*8) {
      tb_set_deck_enabled(core,0,0);
      tb_set_crossfader(core,1.0f);
      tb_set_deck_eq(core,1,0,-3); // cut low a few dB while B is solo
      cross=true;
    }
    if(!autoBack && at>=sr*12) {
      tb_set_deck_enabled(core,0,1);
      tb_schedule_pattern_automix(core,0,1);
      autoBack=true;
    }
    const auto n=std::min<uint32_t>(256,frames-at);
    tb_render(core,left.data(),right.data(),n);
    for(uint32_t i=0;i<n;++i) {
      const auto pcm=[](float v) -> uint16_t {
        return uint16_t(int16_t(std::lround(std::clamp(v,-1.0f,1.0f)*32767)));
      };
      u16(out,pcm(left[i]));u16(out,pcm(right[i]));
    }
    at+=n;
  }
  tb_destroy(core);
  if (!out) return 1;
  std::cout << "WAV: 0-4s A, 4-8s A/B, 8-12s B+EQ, 12-16s B to A pattern AutoMix.\n";
}
