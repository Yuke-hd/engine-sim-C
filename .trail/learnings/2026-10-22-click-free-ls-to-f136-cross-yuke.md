---
title: Click-free LS-to-F136 cross-fade validation
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-6-f136-profile
touches:
  - Sources/EngineSound/CrossfadeMixer.swift
  - Sources/EngineSound/EngineSoundPlayer.swift
  - swift/Tests/EngineSoundProfileTests/ProfileSwitchTests.swift
---

## Decided
The producer's startup/switch/stop gain stage lives in internal CrossfadeMixer so tests can feed it real LS and F136 PCM deterministically via @testable import (debug swift test and Simulator xcodebuild). The click test picks the LS block boundary and F136 offset with the largest splice jump and bounds every output step by 0.8*max source step + 0.8*65535/fadeFrames + 1, the most a linear fade can add. At 3000 RPM, 1000 Hz sim: abrupt step ~31000 vs bound ~1200; replacing the ramp with a step gain fails the test.
## Watch out
engine_sim offline renders are not bit-identical between runs (splice jump and source step vary slightly), so derive bounds from the rendered data rather than hard-coding sample values.
