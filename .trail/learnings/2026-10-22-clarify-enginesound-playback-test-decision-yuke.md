---
title: Clarify EngineSound playback test decision
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-2-engine-sound-player
touches:
  - Package.swift
  - Sources/EngineSound/EngineSoundPlayer.swift
  - Sources/EngineSound/RingBuffer.swift
  - Sources/EngineSound/ToneSource.swift
  - swift/Sources/EngineSoundRing/EngineSoundRing.c
  - swift/Sources/EngineSoundRing/include/EngineSoundRing.h
  - swift/Tests/EngineSoundTests/PlaybackTests.swift
  - swift/Tests/EngineSoundTests/RingBufferTests.swift
---

## Decided
The EngineSound playback implementation and iOS Simulator playback tests are intended. The earlier learning ruled out only passing ENGINE_SOUND_PLAYBACK=1 as an xcodebuild command-line build setting to enable XCTest; it did not rule out playback code or tests. The final iPhone 17 Pro Simulator run passed five EngineSound tests with zero skips, including 60 seconds of ToneSource playback with zero measured underruns.

## Tried and ruled out
No playback implementation was rejected. Only the environment-variable opt-in mechanism was rejected because the test process did not receive it.

## Watch out
Trail may interpret the earlier narrow 'ruled out' wording as rejecting playback generally. Keep this clarification with the PR when explaining that conflict.
