// Checks ConvolutionFilter::f on random data at every ring-buffer wraparound
// position for several lengths. The NEON path (AArch64) must match an exact
// double-precision convolution within 1e-5 of the output RMS; the scalar
// fallback must reproduce the original float loop bit for bit.
#include "convolution_filter.h"

#include <cmath>
#include <cstdio>
#include <random>
#include <vector>

namespace {
#if defined(__ARM_NEON) && defined(__aarch64__)
    using Accumulator = double; // exact reference for the reordered NEON sum
    constexpr bool kBitExact = false;
#else
    using Accumulator = float;  // the original scalar loop, unchanged
    constexpr bool kBitExact = true;
#endif

    // Original two-loop implementation, kept here as the reference.
    double referenceStep(std::vector<float> &reg, const std::vector<float> &ir, int &offset, float sample) {
        const int n = static_cast<int>(ir.size());
        reg[offset] = sample;
        Accumulator result = 0;
        for (int i = 0; i < n - offset; ++i) result += Accumulator(ir[i]) * reg[i + offset];
        for (int i = n - offset; i < n; ++i) result += Accumulator(ir[i]) * reg[i - (n - offset)];
        offset = (offset - 1 + n) % n;
        return result;
    }

    bool checkLength(int n, std::mt19937 &rng) {
        std::uniform_real_distribution<float> dist(-1.0f, 1.0f);
        ConvolutionFilter filter;
        filter.initialize(n);
        std::vector<float> ir(n);
        for (int i = 0; i < n; ++i) ir[i] = filter.getImpulseResponse()[i] = dist(rng);

        std::vector<float> reg(n, 0.0f);
        int offset = 0;
        // Three full passes so every offset is visited with a filled register.
        const int steps = 3 * n + 7;
        std::vector<double> got(steps), want(steps);
        double sumSquares = 0;
        for (int s = 0; s < steps; ++s) {
            const float x = dist(rng);
            got[s] = filter.f(x);
            want[s] = referenceStep(reg, ir, offset, x);
            sumSquares += double(want[s]) * want[s];
        }
        filter.destroy();

        const double rms = std::sqrt(sumSquares / steps);
        double worst = 0;
        for (int s = 0; s < steps; ++s) worst = std::fmax(worst, std::fabs(double(got[s]) - want[s]));
        const bool ok = rms > 0 && (kBitExact ? worst == 0 : worst <= 1e-5 * rms);
        std::printf("%s n=%d max|err|=%.3g rms=%.3g rel=%.3g\n", ok ? "ok  " : "FAIL", n, worst, rms, worst / rms);
        return ok;
    }
}

int main() {
    std::mt19937 rng(12345);
    const int lengths[] = {1, 2, 3, 4, 5, 7, 15, 16, 17, 31, 33, 63, 64, 65, 100, 257, 1000, 4097, 10000};
    bool ok = true;
    for (int n : lengths) ok = checkLength(n, rng) && ok;
    std::printf("%s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}
