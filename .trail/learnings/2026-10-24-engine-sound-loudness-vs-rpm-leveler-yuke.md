---
title: "engine sound loudness vs RPM: leveler is the cause"
author: Yuke-hd
date: 2026-10-24
branch: master
cost: { minutes: 2, tokens: 64289 }
touches:
  - src/leveling_filter.cpp
  - swift/engine_sim_core.cpp
  - Package.swift
---

## Decided
Output loudness not rising with RPM (and dipping around 3000-3500 and 5000-5500 on the LS V8) comes from Synthesizer's LevelingFilter (src/leveling_filter.cpp), not the physics. With the leveler bypassed (fixed gain), raw exhaust signal rises ~47 dB from 1000 to 6000 rpm at 0.5 throttle on dyno hold. The leveler normalizes *peak* to levelerTarget (16000 in swift/engine_sim_core.cpp), so output RMS is flat above 1500 rpm and drops where the waveform's crest factor rises (~3.1 at 3000 vs ~2.3 at 2000/4000). Idle is quiet because gain clamps at levelerMaxGain 1.9.
## Tried and ruled out
Antialiasing (1900 Hz per channel), DC filter, buffer underrun: RPM held exactly and no starvation; not the cause.
## Watch out
Measure by compiling the Package.swift sources plus a harness that #includes swift/engine_sim_core.cpp, then set m_levelingFilter.p_minLevel = p_maxLevel to a fixed gain to bypass AGC. Raw signal also has a physical plateau at 2500-3000 rpm (wave tuning), which the peak leveler makes worse.
