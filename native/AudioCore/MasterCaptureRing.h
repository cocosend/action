#ifndef TRACKBUILDER_MASTER_CAPTURE_RING_H
#define TRACKBUILDER_MASTER_CAPTURE_RING_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct TBCaptureRing TBCaptureRing;
// Single producer (audio mixer tap) / single consumer (off-thread WAV writer).
// Preallocates buffers; push/pop never allocate, wait, lock or perform I/O.
TBCaptureRing *tb_capture_create(size_t capacity_frames);
void tb_capture_destroy(TBCaptureRing *ring); // only after writer and tap have stopped
size_t tb_capture_push(TBCaptureRing *ring, const float *left,
                       const float *right, size_t frames);
size_t tb_capture_pop(TBCaptureRing *ring, float *left,
                      float *right, size_t capacity_frames);
void tb_capture_stop(TBCaptureRing *ring);
int tb_capture_active(const TBCaptureRing *ring);
size_t tb_capture_available(const TBCaptureRing *ring);
// Includes a callback that began before stop and is still publishing samples.
uint32_t tb_capture_inflight(const TBCaptureRing *ring);
uint64_t tb_capture_dropped(const TBCaptureRing *ring);
#ifdef __cplusplus
}
#endif
#endif
