---
title: leveler RMS detector + partial compression tuning for LS V8
author: Yuke-hd
date: 2026-10-24
branch: master
cost: { minutes: 3, tokens: 30315 }
touches:
  - include/leveling_filter.h
  - include/synthesizer.h
  - src/leveling_filter.cpp
  - src/synthesizer.cpp
  - swift/engine_sim_core.cpp
---

## Decided
LevelingFilter gained an RMS detector and a ratio/reference (AudioParameters levelerRmsDetector, levelerRatio, levelerReference, levelerRmsTime). Defaults (peak, ratio 1, reference 0) reproduce the old behaviour exactly. Swift core uses RMS, ratio 0.7, reference 340000 (LS V8 raw RMS at 6000 rpm), target 8000: output rises ~14 dB from 1000 to 6000 rpm with no samples over the 20000 soft-limiter knee.
## Tried and ruled out
RMS detector at ratio 1: removes the 3000-3500 dips and clipping but stays flat, so revving still sounds like it isn't getting louder. Ratio 0.6: idle too quiet (-33 dBFS). Ratio 0.8/target 8000 also works (~9.5 dB rise) if the rise feels too strong.
## Watch out
levelerReference is engine-specific (it depends on raw exhaust signal scale, e.g. audioVolume); retune it per engine. levelerMin/MaxGain used to be applied only in Synthesizer::initialize; they're now refreshed every render block like the other leveler params. A small physical plateau at 2500-3000 rpm and a dip at 5000 rpm stay; those come from the physics, not the leveler.
