---
title: EngineSound session events and playback opt-in clarification
author: Codex
date: 2026-10-23
branch: codex/gh-5-session-thermal
touches:
  - Sources/EngineSound/EngineSoundPlayer.swift
  - Sources/EngineSound/EngineSoundSession.swift
  - swift/Tests/EngineSoundTests/SessionTests.swift
  - swift/BRIDGE.md
---

## Decided
Keep the host's playback request in `EngineSoundPlayer` while interruption,
output-route loss, or critical thermal state temporarily stops the engine and
joins the producer. A separate `EngineSoundSession` supplies device events and
owns audio-session activation; its iOS adapter observes AVAudioSession and
ProcessInfo notifications. Thermal frequency recommendations reach compatible
sources on the producer thread, serialized with rendering. Host apps own scene
and background lifecycle and decide when to request playback.

## Clarification
The older playback learning records that `ENGINE_SOUND_PLAYBACK=1` set on the
`xcodebuild` command line did not reach XCTest. Playback tests therefore run
directly on iOS and skip on macOS. The later clarification learning confirms
that the playback implementation and Simulator tests are intended. Some
`trail check` findings for playback files reflect the earlier wording rather
than a conflict with this session change.

## Watch out
Output route changes must stop and join the old producer even if the new route
is immediately available; then playback can restart if the host still requests
it. iOS Simulator tests verify state transitions but cannot establish real
headphone, Bluetooth, or speaker handoff quality; those need hardware checks.
