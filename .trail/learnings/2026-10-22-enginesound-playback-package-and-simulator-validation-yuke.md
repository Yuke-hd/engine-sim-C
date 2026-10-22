---
title: EngineSound playback package and Simulator validation
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
EngineSound keeps the neutral Swift source protocol in its existing Sources target. A small C11 atomic SPSC ring backs the Swift wrapper because the AVAudioSourceNode callback must read without locks or allocation. The producer owns source rendering, fades, and source replacement.

## Tried and ruled out
Setting ENGINE_SOUND_PLAYBACK=1 on the xcodebuild command line only changed a build setting; XCTest did not receive it. The playback test instead runs on iOS and skips on macOS.

## Watch out
A managed worktree may need explicit access to initialize the solver submodule and run Simulator tools. Read the xcresult summary to confirm a 60-second test ran rather than relying on xcodebuild exit status when output is quiet. A headless Simulator test cannot establish manual listening quality.
