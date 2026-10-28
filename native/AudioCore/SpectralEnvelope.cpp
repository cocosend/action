#include "SpectralEnvelope.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <new>
#include <vector>

namespace {
constexpr size_t bands = 5;
constexpr std::array<double, 4> cutoffs = {120., 500., 2000., 6500.};
}

struct TBSpectralEnvelope {
    const double sampleRate;
    const uint64_t totalFrames;
    const uint32_t binCount;
    uint64_t processed = 0;
    std::vector<float> peaks;
    std::vector<double> energy;
    std::vector<uint64_t> counts;
    std::array<std::array<double, 4>, 2> poles = {};
    std::array<double, 4> coefficients = {};
    explicit TBSpectralEnvelope(double rate, uint64_t total, uint32_t bins)
        : sampleRate(rate), totalFrames(total), binCount(bins), peaks(bins, 0.f),
          energy(size_t(bins) * bands, 0.), counts(bins, 0) {
        for (size_t i = 0; i < cutoffs.size(); ++i) {
            // These are small-signal first-order analysis filters; the upper
            // bands are discarded at Nyquist if cutoff exceeds the device.
            coefficients[i] = 1. - std::exp(-2. * 3.14159265358979323846 *
                                              std::min(cutoffs[i], sampleRate * 0.45) /
                                              sampleRate);
        }
    }
};

extern "C" TBSpectralEnvelope *tb_spectral_create(double rate, uint64_t total, uint32_t bins) {
    if (!std::isfinite(rate) || rate < 8000. || rate > 192000. || total == 0 ||
        total > uint64_t(192000) * 60 * 60 * 12 || bins < 16 || bins > 4096) return nullptr;
    return new (std::nothrow) TBSpectralEnvelope(rate, total, bins);
}
extern "C" void tb_spectral_destroy(TBSpectralEnvelope *analysis) { delete analysis; }
extern "C" uint64_t tb_spectral_consumed(const TBSpectralEnvelope *analysis) {
    return analysis ? analysis->processed : 0;
}
extern "C" size_t tb_spectral_push(TBSpectralEnvelope *analysis, const float *left,
                                    const float *right, size_t frames) {
    if (!analysis || !left || !right || frames == 0) return 0;
    const size_t available = size_t(analysis->totalFrames - analysis->processed);
    const size_t count = std::min(available, frames);
    for (size_t index = 0; index < count; ++index) {
        const double l = std::isfinite(left[index]) ? double(left[index]) : 0.;
        const double r = std::isfinite(right[index]) ? double(right[index]) : 0.;
        // Calculate spectral energy independently for left and right so a
        // phase-inverted stereo recording is NOT displayed as silent.
        // A direct (L+R)/2 collapse cancels many legitimate wide stereo FX.
        const std::array<double, 2> channels = {
            std::clamp(l, -4., 4.), std::clamp(r, -4., 4.)
        };
        const size_t bin = std::min<size_t>(analysis->binCount-1,
             size_t((static_cast<long double>(analysis->processed + index) * analysis->binCount) /
                    analysis->totalFrames));
        const double peak = std::max(std::abs(l), std::abs(r));
        analysis->peaks[bin] = std::max(analysis->peaks[bin],
                                         float(std::min(peak, 4.)));
        for (size_t channel = 0; channel < 2; ++channel) {
            const double x = channels[channel];
            double previous = 0.;
            for (size_t band = 0; band < 4; ++band) {
                const double low = analysis->poles[channel][band] +=
                    analysis->coefficients[band] *
                       (x - analysis->poles[channel][band]);
                const double separated = low - previous;
                previous = low;
                analysis->energy[bin*bands+band] += separated*separated * 0.5;
            }
            const double hi = x - previous;
            analysis->energy[bin*bands+4] += hi*hi * 0.5;
        }
        ++analysis->counts[bin];
    }
    analysis->processed += count;
    return count;
}
extern "C" int tb_spectral_finish(const TBSpectralEnvelope *analysis, float *peaks,
                                     float *bandEnergy, uint32_t bins) {
    if (!analysis || !peaks || !bandEnergy || bins != analysis->binCount) return 0;
    const float maxPeak = *std::max_element(analysis->peaks.begin(), analysis->peaks.end());
    double maxRMS = 0.;
    for (uint32_t i = 0; i < bins; ++i) {
        const double denom = double(std::max<uint64_t>(1, analysis->counts[i]));
        for (size_t b = 0; b < bands; ++b) {
            const double rms = std::sqrt(analysis->energy[i*bands+b] / denom);
            maxRMS = std::max(maxRMS, rms);
        }
    }
    for (uint32_t i = 0; i < bins; ++i) {
        peaks[i] = maxPeak > 0.f ? std::clamp(analysis->peaks[i]/maxPeak, 0.f, 1.f) : 0.f;
        const double denom = double(std::max<uint64_t>(1, analysis->counts[i]));
        for (size_t b = 0; b < bands; ++b) {
            const double rms = std::sqrt(analysis->energy[i*bands+b] / denom);
            // Shared normalization for all five bands means the colors
            // still represent the audio's relative frequency balance.
            bandEnergy[i*bands+b] = maxRMS > 0. ?
                float(std::clamp(rms/maxRMS, 0., 1.)) : 0.f;
        }
    }
    return 1;
}
