---
title: "F136 gate: 10 kHz default supersedes 1000 Hz"
author: Yuke-hd
date: 2026-10-23
branch: codex/gh-6-f136-profile
---

## Decided
This supersedes the frequency in 2026-10-22-f136-device-gate-moved-to-median-yuke.md and 2026-10-22-live-demo-throttle-needs-4000-hz-yuke.md (learnings are never edited). The issue #6 iPhone gate now runs at the production default simulation frequency: engine_sim_create(profile, 0), ENGINE_SIM_DEFAULT_FREQUENCY = 10 kHz, confirmed by engine_sim_simulation_frequency(core) in the report. The gate is the strict median F136 compute/audio ratio < 0.7 (owner confirmed strict, not <= 0.7) over five timed 3 s renders at 3000 RPM after one discarded warm-up. LS stays an informational baseline. ProcessInfo thermal state is printed before and after the gate. 1000 Hz was only the interim gate frequency and is now a reference line, as is 4000 Hz. 4000 Hz is only the live demo's choice, not a gate setting. Cool-start iPhone 12 Pro: LS median 0.633, F136 median 0.629.

## Watch out
Heat adds about 0.06 at 10 kHz (warm F136 is about 0.70, a FAIL under the strict bound). Compare cool (nominal) starts only. 1000-2000 Hz still trips the combustion_chamber.cpp:417 NaN assert at low throttle and is not filed as an issue. Physics optimization is tracked in issue #16.
