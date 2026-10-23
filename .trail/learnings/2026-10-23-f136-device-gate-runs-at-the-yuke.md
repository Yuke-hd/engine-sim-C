---
title: F136 device gate runs at the 10 kHz default
author: Yuke-hd
date: 2026-10-23
branch: codex/gh-6-f136-profile
touches:
  - swift/Benchmarks/F136DeviceBenchmark/App/F136DeviceBenchmarkApp.swift
  - swift/README.md
---

## Decided
The F136 device gate (issue #6) runs at the production default ENGINE_SIM_DEFAULT_FREQUENCY (10 kHz, engine_sim_create(profile, 0)), not 1000 Hz. Gate stays F136 median < 0.7; LS baseline, 1000 Hz and 4000 Hz lines are informational. On iPhone 12 Pro with the NEON convolution, a cool start gives F136 median about 0.63-0.65 and LS about 0.63.

## Tried and ruled out
Speeding up the synthesizer further: at 10 kHz the physics thread (solver ~0.28 + fluid substeps ~0.34 of the ratio) is the critical path; the audio thread waits most of the time.

## Watch out
Heat raises 10 kHz ratios by about 0.06 (warm F136 median about 0.70, at the gate edge). The report prints ProcessInfo thermalState before and after; compare only cool (nominal) starts. Live demo stays at 4000 Hz because 1000-2000 Hz trips the combustion_chamber.cpp NaN assert at low throttle.
