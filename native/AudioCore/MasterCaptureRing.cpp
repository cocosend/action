#include "MasterCaptureRing.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <new>
#include <vector>

struct TBCaptureRing {
    explicit TBCaptureRing(size_t capacity)
        : capacity(capacity), left(capacity, 0.f), right(capacity, 0.f) {}
    size_t capacity;
    std::vector<float> left, right;
    std::atomic<uint64_t> writeIndex{0};
    std::atomic<uint64_t> readIndex{0};
    std::atomic<uint64_t> dropped{0};
    std::atomic<bool> active{true};
    std::atomic<uint32_t> inFlight{0};
};

extern "C" TBCaptureRing *tb_capture_create(size_t capacity) {
    // Fits bounded memory and provides >1 second at normal sample rates.
    if (capacity < 2048 || capacity > (1u << 20)) return nullptr;
    return new (std::nothrow) TBCaptureRing(capacity);
}

extern "C" void tb_capture_destroy(TBCaptureRing *ring) { delete ring; }

extern "C" size_t tb_capture_push(TBCaptureRing *ring, const float *l,
                                    const float *r, size_t frames) {
    if (!ring || !l || !r || !ring->active.load(std::memory_order_acquire)) return 0;
    ring->inFlight.fetch_add(1, std::memory_order_acq_rel);
    if (!ring->active.load(std::memory_order_acquire)) {
        ring->inFlight.fetch_sub(1, std::memory_order_release);
        return 0;
    }
    const uint64_t read = ring->readIndex.load(std::memory_order_acquire);
    const uint64_t write = ring->writeIndex.load(std::memory_order_relaxed);
    const size_t room = static_cast<size_t>(ring->capacity - (write - read));
    const size_t accepted = std::min(frames, room);
    for (size_t i = 0; i < accepted; ++i) {
        const size_t index = static_cast<size_t>((write + i) % ring->capacity);
        // Drop any nonfinite audio to silence, never emit invalid WAV values.
        ring->left[index] = std::isfinite(l[i]) ? l[i] : 0.f;
        ring->right[index] = std::isfinite(r[i]) ? r[i] : 0.f;
    }
    ring->writeIndex.store(write + accepted, std::memory_order_release);
    if (accepted < frames) ring->dropped.fetch_add(frames - accepted, std::memory_order_relaxed);
    ring->inFlight.fetch_sub(1, std::memory_order_release);
    return accepted;
}

extern "C" size_t tb_capture_pop(TBCaptureRing *ring, float *l, float *r,
                                   size_t frames) {
    if (!ring || !l || !r || !frames) return 0;
    const uint64_t read = ring->readIndex.load(std::memory_order_relaxed);
    const uint64_t write = ring->writeIndex.load(std::memory_order_acquire);
    const size_t count = std::min(frames, static_cast<size_t>(write - read));
    for (size_t i = 0; i < count; ++i) {
        const size_t index = static_cast<size_t>((read + i) % ring->capacity);
        l[i] = ring->left[index];
        r[i] = ring->right[index];
    }
    ring->readIndex.store(read + count, std::memory_order_release);
    return count;
}

extern "C" void tb_capture_stop(TBCaptureRing *ring) {
    if (ring) ring->active.store(false, std::memory_order_release);
}
extern "C" int tb_capture_active(const TBCaptureRing *ring) {
    return ring && ring->active.load(std::memory_order_acquire);
}
extern "C" size_t tb_capture_available(const TBCaptureRing *ring) {
    if (!ring) return 0;
    return static_cast<size_t>(ring->writeIndex.load(std::memory_order_acquire) -
                               ring->readIndex.load(std::memory_order_acquire));
}
extern "C" uint32_t tb_capture_inflight(const TBCaptureRing *ring) {
    return ring ? ring->inFlight.load(std::memory_order_acquire) : 0;
}
extern "C" uint64_t tb_capture_dropped(const TBCaptureRing *ring) {
    return ring ? ring->dropped.load(std::memory_order_acquire) : 0;
}
