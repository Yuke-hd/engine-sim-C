#include "../include/convolution_filter.h"

#include <assert.h>
#include <string.h>

#if defined(__ARM_NEON) && defined(__aarch64__)
#include <arm_neon.h>
#endif

namespace {
    // Returns acc + sum(a[i] * b[i]) for i in [0, n). The NEON path uses
    // independent accumulators to break the serial FMA latency chain, so its
    // summation order (and last-bit rounding) differs from the scalar loop.
    inline float dotAccumulate(float acc, const float *a, const float *b, int n) {
#if defined(__ARM_NEON) && defined(__aarch64__)
        float32x4_t s0 = vdupq_n_f32(0.0f);
        float32x4_t s1 = vdupq_n_f32(0.0f);
        float32x4_t s2 = vdupq_n_f32(0.0f);
        float32x4_t s3 = vdupq_n_f32(0.0f);

        int i = 0;
        for (; i + 16 <= n; i += 16) {
            s0 = vfmaq_f32(s0, vld1q_f32(a + i), vld1q_f32(b + i));
            s1 = vfmaq_f32(s1, vld1q_f32(a + i + 4), vld1q_f32(b + i + 4));
            s2 = vfmaq_f32(s2, vld1q_f32(a + i + 8), vld1q_f32(b + i + 8));
            s3 = vfmaq_f32(s3, vld1q_f32(a + i + 12), vld1q_f32(b + i + 12));
        }

        for (; i + 4 <= n; i += 4) {
            s0 = vfmaq_f32(s0, vld1q_f32(a + i), vld1q_f32(b + i));
        }

        float sum = vaddvq_f32(vaddq_f32(vaddq_f32(s0, s1), vaddq_f32(s2, s3)));
        for (; i < n; ++i) {
            sum += a[i] * b[i];
        }

        return acc + sum;
#else
        for (int i = 0; i < n; ++i) {
            acc += a[i] * b[i];
        }

        return acc;
#endif
    }
}

ConvolutionFilter::ConvolutionFilter() {
    m_shiftRegister = nullptr;
    m_impulseResponse = nullptr;

    m_shiftOffset = 0;
    m_sampleCount = 0;
}

ConvolutionFilter::~ConvolutionFilter() {
    assert(m_shiftRegister == nullptr);
    assert(m_impulseResponse == nullptr);
}

void ConvolutionFilter::initialize(int samples) {
    m_sampleCount = samples;
    m_shiftOffset = 0;
    m_shiftRegister = new float[samples];
    m_impulseResponse = new float[samples];

    memset(m_shiftRegister, 0, sizeof(float) * samples);
    memset(m_impulseResponse, 0, sizeof(float) * samples);
}

void ConvolutionFilter::destroy() {
    delete[] m_shiftRegister;
    delete[] m_impulseResponse;

    m_shiftRegister = nullptr;
    m_impulseResponse = nullptr;
}

float ConvolutionFilter::f(float sample) {
    m_shiftRegister[m_shiftOffset] = sample;

    // The impulse response runs over two contiguous ring-buffer segments:
    // [m_shiftOffset, m_sampleCount) and then [0, m_shiftOffset).
    const int head = m_sampleCount - m_shiftOffset;
    float result = dotAccumulate(0.0f, m_impulseResponse, m_shiftRegister + m_shiftOffset, head);
    result = dotAccumulate(result, m_impulseResponse + head, m_shiftRegister, m_shiftOffset);

    m_shiftOffset = (m_shiftOffset - 1 + m_sampleCount) % m_sampleCount;

    return result;
}
