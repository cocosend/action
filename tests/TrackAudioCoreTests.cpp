#include "TrackAudioCore.h"
#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <iostream>
#include <numeric>
#include <vector>

#define CHECK(expression) do { \
  if (!(expression)) { \
    std::cerr << "CHECK failed: " << #expression << " (" << __FILE__ << ":" << __LINE__ << ")\n"; \
    std::abort(); \
  } \
} while (false)

static double renderRMS(TBEngine *engine, size_t frames) {
  std::vector<float> l(frames), r(frames);
  tb_render(engine, l.data(), r.data(), frames);
  double total = 0.0;
  for (size_t i = 0; i < frames; ++i) {
    CHECK(std::isfinite(l[i]) && std::isfinite(r[i]));
    CHECK(std::fabs(l[i]) < 1.0f && std::fabs(r[i]) < 1.0f);
    total += double(l[i]) * l[i];
  }
  return std::sqrt(total / static_cast<double>(frames));
}

int main() {
  CHECK(tb_create(0) == nullptr);
  CHECK(tb_create(NAN) == nullptr);
  TBEngine *e = tb_create(48000);
  CHECK(e != nullptr);
  // No audio until the user explicitly starts transport.
  CHECK(renderRMS(e, 48000) == 0.0);
  CHECK(tb_get_step(e, 0, TBInstrumentKick, 0) == 1);
  CHECK(tb_get_step(e, 1, TBInstrumentBass, 3) == 1);
  CHECK(tb_get_step(e, 2, TBInstrumentKick, 0) == 0);
  tb_set_step(e, 0, TBInstrumentKick, 0, 0);
  CHECK(tb_get_step(e, 0, TBInstrumentKick, 0) == 0);
  tb_set_step(e, 0, TBInstrumentKick, 0, 1);
  CHECK(tb_get_step(e, 0, TBInstrumentKick, 0) == 1);
  tb_set_step(e, -1, 1, 0, 1);
  tb_set_step(e, 0, 99, 0, 1);
  tb_set_step(e, 0, 1, 18, 1);
  tb_set_bpm(e, NAN);
  tb_set_bpm(e, 132);
  tb_set_crossfader(e, 0.0f);
  tb_set_master_gain(e, 0.75f);
  tb_set_playing(e, 1);
  const double rmsA = renderRMS(e, 48000 * 2);
  CHECK(rmsA > 0.001 && rmsA < 0.6);
  tb_set_crossfader(e, 1.0f);
  const double rmsB = renderRMS(e, 48000 * 2);
  CHECK(rmsB > 0.001 && rmsB < 0.6);
  CHECK(tb_current_step(e) >= 0 && tb_current_step(e) < 16);
  tb_set_bpm(e, 200);
  CHECK(renderRMS(e, 48000) > 0.001);
  tb_request_reset(e);
  tb_set_playing(e, 0);
  CHECK(renderRMS(e, 48000) == 0.0);
  tb_set_playing(e, 1);
  CHECK(renderRMS(e, 48000) > 0.001);
  tb_set_master_gain(e, 0.0f);
  renderRMS(e, 4096); // sufficient gain smoothing
  CHECK(renderRMS(e, 4096) < 0.0001);
  tb_destroy(e);

  // Offline render must be bit-for-bit independent of callback block sizes.
  TBEngine *one = tb_create(44100);
  TBEngine *two = tb_create(44100);
  tb_set_playing(one, 1);
  tb_set_playing(two, 1);
  constexpr size_t count = 20000;
  std::vector<float> wholeL(count), wholeR(count), chunkL(count), chunkR(count);
  tb_render(one, wholeL.data(), wholeR.data(), count);
  for (size_t offset = 0; offset < count;) {
    const size_t n = std::min<size_t>(127, count - offset);
    tb_render(two, chunkL.data() + offset, chunkR.data() + offset, n);
    offset += n;
  }
  CHECK(wholeL == chunkL && wholeR == chunkR);
  tb_destroy(one);
  tb_destroy(two);
  std::cout << "TrackAudioCore: all DSP and transport assertions passed\n";
}
