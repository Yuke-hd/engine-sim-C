---
title: F136 source port and impulse response mapping
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-6-f136-profile
touches:
  - swift/f136_v8_builder.cpp
  - swift/f136_v8_impulse_response.cpp
  - swift/engine_sim_core.cpp
---

## Decided
- The F136 script in assets/engines/atg-video-2/08_ferrari_f136_v8.mr maps bank 0 to wires 1-4 at +45 degrees and bank 1 to wires 5-8 at -45 degrees. Its firing order is 1, 5, 3, 7, 4, 8, 2, 6 with even 90-degree intervals.
- `mild_exhaust_0_reverb` resolves through es/sound-library/impulse_responses.mr to es/sound-library/new/mild_exhaust_reverb.wav at volume 0.01. The F136 C++ builder and embedded WAV must preserve that mapping.
## Tried and ruled out
- Running a Swift package XCTest bundle directly on an iPhone is unsupported because Xcode requires a host app. A temporary host app can provide one, but the Mac also needs a matching iOS development signing account and provisioning profile.
## Watch out
- Keep the selected profile's impulse response, RPM clamp, engine pointer, and destruction path together when adding another profile. Long offline audio tests may be killed by the iOS Simulator test runner; a half-second measurement window resolves the 200/400 Hz firing peaks at 3000/6000 RPM.
