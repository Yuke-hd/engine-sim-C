---
title: Linux is no longer a CI target
author: yk-s-coding-bot
date: 2026-10-23
branch: ci/drop-linux-swift
touches:
  - ".github/workflows/ci.yml"
  - Sources/EngineSound/EngineSoundPlayer.swift
---

## Decided
- The project owner decided Linux is not a target platform. CI (.github/workflows/ci.yml) builds and tests the Swift package only on macos-15; the ubuntu-22.04 matrix entry and the Linux Swift setup step were removed. This supersedes the 'run Swift build/test on Ubuntu plus macOS' decision in 2026-10-22-swiftpm-linux-solver-headers-and-ci-yuke.md.
- Trigger: after PR #9 merged, EngineSound's EngineSoundPlayer.swift imports AVFoundation unconditionally, so the Linux job failed with 'no such module AVFoundation'. The owner chose to drop Linux CI rather than guard the import.

## Watch out
- The earlier C/C++ Linux portability fixes (string.h pre-include, std::fpclassify, <cmath>, C++ runtime link) remain in the tree but are no longer exercised by CI. Do not reintroduce a Linux job without first making EngineSound build on Linux.
