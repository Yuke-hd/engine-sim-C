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
ProcessInfo notifications. Notification handlers enqueue playback work on a
serial control queue so producer joins do not block the main queue. Thermal
frequency recommendations reach compatible sources only on the producer thread,
serialized with rendering. Automatic restart errors are observable through the
player's failure state and callback. Host apps own scene and background
lifecycle and decide when to request playback.

## Tried and ruled out
A command-line build setting as a runtime opt-in: the spawned process did not
receive it. Use explicit platform conditions instead.

## Watch out
Output route changes must stop and join the old producer even if the new route
is immediately available; then playback can restart if the host still requests
it. iOS Simulator tests verify state transitions but cannot establish real
headphone, Bluetooth, or speaker handoff quality; those need hardware checks.
The historical Trail conflict applies only to runner configuration. The later
clarification learning confirms that the package behavior and Simulator checks
are intended.
