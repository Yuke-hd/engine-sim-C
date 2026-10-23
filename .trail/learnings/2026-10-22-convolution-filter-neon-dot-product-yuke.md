---
title: Convolution filter NEON dot product
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-6-f136-profile
touches:
  - src/convolution_filter.cpp
  - swift/Tests/ConvolutionFilter/main.cpp
  - swift/Tests/check_convolution_filter.sh
---

## Decided
ConvolutionFilter::f was 99.7% of render time on iPhone 12 Pro (serial FMA latency chain, ~1.35 ns/tap; impulse responses are clipped to at most 10000 taps). It now runs a NEON dot product with four independent float32x4 accumulators over the two ring-buffer segments, guarded by __ARM_NEON && __aarch64__ (vfmaq_f32/vaddvq_f32 are AArch64-only); other targets keep the original scalar loop unchanged. Device Release ratios at 1000 Hz/3000 RPM dropped from LS 0.818 / F136 1.184 to about 0.099 / 0.111. A vDSP_dotpr prototype was no faster (0.099 / 0.111), so Accelerate is not linked.

## Tried and ruled out
Checking the NEON or scalar sum against a double reference with a fixed 1e-5-of-RMS tolerance fails for the original scalar float loop at ~4k taps (its own serial rounding is ~1.3e-5 of RMS). swift/Tests/check_convolution_filter.sh therefore requires the NEON path within 1e-5 of RMS of an exact double convolution and the scalar fallback (built as x86_64 under Rosetta on Apple silicon) bit-identical to the original float loop.

## Watch out
The reordered NEON sum changes PCM16 output by at most about one LSB, so offline renders are not bit-identical to pre-change captures on ARM.
