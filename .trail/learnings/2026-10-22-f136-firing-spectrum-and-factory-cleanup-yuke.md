---
title: F136 firing spectrum and factory cleanup
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-6-f136-profile
touches:
  - swift/Tests/EngineSimCoreTests/F136V8Tests.swift
  - swift/engine_sim_core.cpp
  - swift/f136_v8_builder.cpp
---

The F136 script uses split-bank exhausts with intentionally asymmetric volumes (0.20 and 0.18), per-cylinder attenuation, and header lengths. At 3000 RPM, a 16384-point Hann-window FFT of rendered mono audio measured the global dominant peak at 99.59 Hz (second engine order); the four-fires-per-revolution component is 199.18 Hz, about 15.5% of the global peak power. At 6000 RPM the global and firing-order peaks coincide at 401.06 Hz. The owner decided to preserve the upstream acoustics and report both peaks; assert the firing-order component within 3%, without pretending it is globally dominant at 3000. Factory exception cleanup must own the core and simulator from allocation onward, and partial builders/engine/synthesizer objects must be safe to destroy. Physical iPhone compute/audio <=0.5 remains unverified without a signing setup.
