---
title: PR 11 documentation and inherited F136 check results
author: yk-s-coding-bot
date: 2026-10-22
branch: codex/gh-7-swift-package-docs
touches:
  - swift/README.md
  - swift/Benchmarks/F136DeviceBenchmark/App/F136DeviceBenchmarkApp.swift
  - src/combustion_chamber.cpp
---

## Decided
- PR #11 changes only package documentation and notices. The new `swift/README.md` product/target table names `EngineSimCore`; it does not change the F136 bank/wire angles, firing order, or source implementation. `trail check` interpreting that prose as a cylinder-mapping change is a false positive.
- The physical-iPhone F136 gate is the signed `swift/Benchmarks/F136DeviceBenchmark` host app, not a SwiftPM XCTest; the base removed the skipped `testIPhoneRenderBenchmark`. README mentions of XCTest on iPhone and the Simulator `xcodebuild test` command restate that limit and do not reintroduce `ENGINE_SOUND_PLAYBACK=1`, so `trail check` flags on `swift/README.md:1` are false positives.
- At 1000 Hz a debug render of either profile at 1000 RPM (and F136 8500 / LS 6000 and 7500 RPM, plus many low-throttle RPMs) hits `assert(false)` at `src/combustion_chamber.cpp:417` (NaN/Inf force). 2000 Hz is not clean either: it still trips the same assert at 5000-6500 RPM with low throttle. 4000, 5000 and 10000 Hz rendered cleanly in the tested combinations. Reproduced with a probe linked against the debug `EngineSimCore` objects. README documents it as a known limitation; it predates #10.

## Watch out
- Preserve the F136 mapping and the host/provisioning limitation recorded in the existing F136 source-port learning. Reassess the hardware benchmark only when a signed physical-iPhone host is available.
