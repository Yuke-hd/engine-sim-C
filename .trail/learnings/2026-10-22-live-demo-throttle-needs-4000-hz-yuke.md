---
title: Live demo throttle needs 4000 Hz simulation
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-6-f136-profile
touches:
  - swift/Benchmarks/F136DeviceBenchmark/App/F136DeviceBenchmarkApp.swift
  - swift/README.md
---

## Decided
The device demo's throttle slider drives engine_sim_set_throttle plus a dyno-held RPM slewed (3000 RPM/s) from the idle preset toward 6500 RPM, applied inside LiveEngineSource.render on the player's worker thread from a lock-protected value the main thread writes, so the core is never touched from the main thread and no source is re-created. EngineSoundPlayer has no control-forwarding API, so this stays in the app. Live playback runs at 4000 Hz; the 1000 Hz benchmark is unchanged. iPhone 12 Pro played both engines through full throttle sweeps and snaps with 0 underruns.

## Tried and ruled out
1000 Hz simulation for live playback with a throttle: on macOS with asserts on, the combustion_chamber.cpp:417 NaN-force assert fires within 6 s for LS at throttle <= 0.1 at every RPM and at 2000 RPM for most throttles, and for F136 at throttle 0 above 2000 RPM. 2000 Hz still trips it at 5000-6500 RPM with low throttle. 4000 Hz passed every tested combination (1000-6500 RPM, throttle 0/0.1/1, and 15 s ramp/snap sweeps from idle 1000/2000/3000).

## Watch out
The Xcode Release build of the SwiftPM package does not define NDEBUG, so engine asserts abort the app on device.
