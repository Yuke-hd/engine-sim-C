---
title: F136 device gate moved to median below 0.7
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-6-f136-profile
touches:
  - swift/Benchmarks/F136DeviceBenchmark/App/F136DeviceBenchmarkApp.swift
  - swift/README.md
---

## Decided
The owner moved the issue #6 physical-iPhone gate from compute/audio <=0.5 to a strict < 0.7, measured as the median of five timed 3 s F136 renders at 3000 RPM, 1000 Hz simulation and 44.1 kHz after one discarded warm-up render. This supersedes the <=0.5 wording in the earlier F136 learnings. The benchmark app also runs the LS V8 as an informational baseline and displays min/median/max; max is shown but not gated. Device data on iPhone 12 Pro (iOS 26.0.1, Release) before this change: single F136 runs 1.186 and 0.819, LS V8 about 0.65, so single runs vary too much to gate on.
## Watch out
At 1000 Hz simulation, 1000 RPM (both profiles), 6000 and 7500 RPM (LS) and 8500 RPM (F136) trip the combustion_chamber.cpp:417 assertion, so the benchmark measures only 3000 RPM. Never commit a DEVELOPMENT_TEAM; pass it on the xcodebuild command line.
