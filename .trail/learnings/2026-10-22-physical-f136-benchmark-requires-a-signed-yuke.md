---
title: Physical F136 benchmark requires a signed iOS host
author: Yuke-hd
date: 2026-10-22
branch: codex/gh-6-f136-profile
touches:
  - swift/Benchmarks/F136DeviceBenchmark/App/F136DeviceBenchmarkApp.swift
  - swift/Tests/EngineSimCoreTests/F136V8Tests.swift
  - swift/README.md
---

## Decided
The issue #6 F136 compute/audio <=0.5 acceptance gate must be measured on a physical iPhone at 1000 Hz simulation and 44.1 kHz audio. Use the checked-in F136DeviceBenchmark iOS app as the signed host; its visible report records device, OS, sample count, elapsed compute time, rendered audio duration, ratio, and pass/fail. Keep PR #10 draft and issue #6 open until the device result is reported.

## Tried and ruled out
A Swift package XCTest bundle cannot run directly on the paired physical iPhone because Xcode requires an app host. A temporary app build was previously blocked by absent signing account/certificate/profile. Do not use a skipped device-only SwiftPM XCTest or an iOS Simulator result as evidence for the physical threshold.

## Watch out
The Xcode project has no team or signing credentials checked in; the owner selects their own team and bundle identifier in Xcode. The app displays the user-assigned device name, so confirm iPhone 12 Pro model in iOS Settings when recording the result.
