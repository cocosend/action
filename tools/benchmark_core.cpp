#include "TrackAudioCore.h"
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <vector>
int main() {
  using Clock=std::chrono::steady_clock;
  for (int rate : {48000, 96000, 192000}) {
    auto *core=tb_create(rate);
    if (!core) return 1;
    tb_set_playing(core, 1);
    tb_set_bpm(core, 145);
    tb_set_deck_delay(core, 0, 0.42f);
    tb_set_deck_delay(core, 1, 0.42f);
    tb_set_deck_eq(core, 0, 2, 5);
    tb_set_deck_eq(core, 1, 0, -5);
    std::vector<float> left(256),right(256);
    const auto t0=Clock::now();
    float peak=0;
    for (int i=0; i<rate*12; i+=256) {
      const int n=std::min(256, rate*12-i);
      tb_render(core,left.data(),right.data(),n);
      for(int j=0;j<n;++j) peak=std::max(peak,std::max(std::abs(left[j]),std::abs(right[j])));
    }
    const double wall=std::chrono::duration<double>(Clock::now()-t0).count();
    const double realtime=12/wall;
    std::cout << "Linux native C++ DSP, stereo, 2 decks+EQ+delay, " << rate << " Hz: "
              << std::fixed << std::setprecision(2) << wall
              << " s to render 12 s (" << realtime << "x realtime), peak " << peak << "\n";
    if (!(peak>0.01f && peak<0.981f && realtime>1.0)) return 2;
    tb_destroy(core);
  }
  // This benchmark is NOT an iPhone CPU/latency, buffer, or underrun claim.
}
