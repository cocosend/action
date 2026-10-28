#ifndef TRACKBUILDER_SPECTRAL_ENVELOPE_H
#define TRACKBUILDER_SPECTRAL_ENVELOPE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Offline-only streaming analysis. NOT called from the real-time audio thread.
// Tracks true peak and approximate low/mid/high frequency energy per timeline
// bin. Five frequency bands are first-order crossover residuals, NOT stems or
// FFT bins. Fixed-size preallocated storage; caller owns output arrays.
typedef struct TBSpectralEnvelope TBSpectralEnvelope;
TBSpectralEnvelope *tb_spectral_create(double sample_rate, uint64_t total_frames,
                                      uint32_t bins);
void tb_spectral_destroy(TBSpectralEnvelope *analysis);
// Mono content may pass the same channel pointer twice. Returns frames consumed.
size_t tb_spectral_push(TBSpectralEnvelope *analysis, const float *left,
                        const float *right, size_t frames);
// peak_output needs bins floats. bands_output needs bins*5 floats: bin-major,
// low to high. Each output normalized to 0..1. Returns 1 on success.
int tb_spectral_finish(const TBSpectralEnvelope *analysis, float *peak_output,
                       float *bands_output, uint32_t bins);
uint64_t tb_spectral_consumed(const TBSpectralEnvelope *analysis);
#ifdef __cplusplus
}
#endif
#endif
