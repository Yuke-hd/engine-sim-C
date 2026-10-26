---
title: RMS leveler target follows RPM and throttle
author: Yuke-hd
date: 2026-10-26
branch: master
cost: { minutes: 14, tokens: 221503 }
touches:
  - Package.swift
  - include/leveling_filter.h
  - include/synthesizer.h
  - src/leveling_filter.cpp
  - src/synthesizer.cpp
  - swift/engine_sim_core.cpp
  - swift/include/EngineSimCore.h
  - swift/TestApp/.gitignore
  - swift/TestApp/EngineSimTester.xcodeproj/project.pbxproj
  - swift/TestApp/EngineSimTester.xcodeproj/project.xcworkspace/contents.xcworkspacedata
---

## Decided
ENGINE_SIM_LEVELER_RPM_SCALED now normalises fully (ratio 1, RMS detector) to a target the core recomputes each frame in renderLoop (updateLevelerTarget in swift/engine_sim_core.cpp): 9000 * (rpm/redline)^0.6 * (0.75 + 0.25*throttle), with speed clamped 0.1-1.1 and eased 0.3 per frame. levelerMaxGain is 4 in this mode. This replaces the ratio-0.7 partial compression with per-engine references.
## Tried and ruled out
Partial compression (ratio 0.7): the raw signal before levelling is much louder at closed throttle (LS about 40x at 4000 rpm), so opening the throttle made output fall by up to 2.6x, mostly between 0 and 20%. Users heard it as "very low volume past 10% throttle" on all engines. A linear (0.2+0.8x) speed curve with an 8500 base was 2-4 dB too quiet mid-range.
## Watch out
Measure with full pipeline output RMS across throttle 0-1 at several RPMs, not at hold_rpm's fixed 0.5 throttle. hold_rpm resets throttle to 0.5, so callers must reapply throttle after it. M177 at 1000 rpm still hits the 4x gain cap.
