---
title: "M177 V8 port: phasing check and leveler reference"
author: Yuke-hd
date: 2026-10-24
branch: master
cost: { minutes: 30, tokens: 295341 }
touches:
  - Package.swift
  - include/leveling_filter.h
  - include/synthesizer.h
  - src/leveling_filter.cpp
  - src/synthesizer.cpp
  - swift/engine_sim_core.cpp
  - swift/include/EngineSimCore.h
  - swift/TestApp/EngineSimTester.xcodeproj/project.pbxproj
  - swift/TestApp/EngineSimTester.xcodeproj/project.xcworkspace/contents.xcworkspacedata
  - swift/TestApp/EngineSimTester/ContentView.swift
---

## Decided
The M177 (Mercedes-AMG 4.0 hot-vee) is modelled from published specs, because there is no upstream .mr script for it: 83 x 92 mm, 10.5:1, cross-plane journals {0,270,90,180}, firing order 1-5-4-8-6-3-7-2, redline 7000 and rev limit 7200. The cams, port flows and rod length are estimates. engine-sim has no turbo model, so the engine is naturally aspirated. It reuses the F136 impulse response. Its RMS leveler reference is 43000, which is its raw RMS at hold_rpm (throttle 0.5) at the 7000 sweep top. The F136 measures 48000 at 8500, matching its existing reference.

## Tried and ruled out
Filtered dyno torque and chamber m_peakTemperature are no use for checking that combustion happens. Every profile, the LS included, reports negative torque that grows with RPM, and the numbers are identical with ignition off. m_peakTemperature is sampled in flow() before the burn.

## Watch out
To check firing phasing, step sim->simulateStep() yourself. For each cylinder, record m_nBurntFuel and the chamber volume, normalised so 0 is TDC and 1 is BDC, at the moment m_lit goes from false to true. A correct port lights every cylinder once per cycle at a volume of about 0.01-0.02.
