---
title: Linux portability fixes for downstream SwiftPM consumers
author: Yuke-hd
date: 2026-10-22
branch: fix/ci-fpclassify-linux
cost: { minutes: 8, tokens: 58916 }
touches:
  - src/audio_buffer.cpp
  - src/exhaust_system.cpp
  - src/governor.cpp
  - src/simulator.cpp
  - Package.swift
  - ".github/workflows/ci.yml"
  - src/synthesizer.cpp
---

## Decided
Fix missing std math declarations at the source: std::fpclassify in synthesizer.cpp and #include <cmath> in audio_buffer, simulator, exhaust_system, governor. Link c++ only on Apple platforms and stdc++ on Linux in Package.swift. Dropped the `-Xcxx -include -Xcxx math.h` flag from ci.yml so CI builds the way downstream does.

## Tried and ruled out
Keeping the math.h flag in CI: it hid the errors, and the downstream esp-can-companion Linux build (no such flag) failed on fpclassify.

## Watch out
Each Linux error is hidden behind the previous one; fpclassify was followed by std::abs in audio_buffer.cpp. A local macOS build cannot show these, so only the Linux CI run confirms the fix. The solver submodule's -include string.h unsafeFlags patch is still in place.
