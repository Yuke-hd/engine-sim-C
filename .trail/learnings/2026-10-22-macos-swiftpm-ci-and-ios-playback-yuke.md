---
title: macOS SwiftPM CI and iOS playback tests
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
touches:
  - ".github/workflows/cmake.yml"
---

## Decided
Keep the macOS Swift package build and test leg for general package and EngineSimCore coverage. Playback tests are iOS-specific and skip on macOS; add iOS Simulator coverage separately if those tests need CI execution.

## Tried and ruled out
Removing macOS package CI because the playback test skips there would also drop useful cross-platform SwiftPM coverage and would not add iOS playback coverage.

## Watch out
A macOS `swift test` run does not validate iOS-only playback tests. Use an iOS Simulator test destination for playback coverage when configuring that job.
