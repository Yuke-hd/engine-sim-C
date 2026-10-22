---
title: XCTest runner needs the macOS Xcode Swift toolchain
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
touches:
  - ".github/workflows/ci.yml"
---

## Decided
Run SwiftPM XCTest on macOS with the Swift toolchain bundled with the runner's selected Xcode. Keep `swift-actions/setup-swift@v2` pinned to Swift 6.0 on Linux, where the Swift toolchain does not depend on Xcode's XCTest frameworks.

## Tried and ruled out
The hosted macOS job built with setup-swift's Swift 6.0.3 and all 6 XCTest cases passed, but the SwiftPM testing helper then exited with signal 5 because `libXCTestSwiftSupport.dylib` could not load `XCTestCore.framework` from Xcode 16.4 or the standalone toolchain.

## Watch out
A passing XCTest summary can still be followed by a failing SwiftPM test helper process. Check the end of the macOS log for framework-load errors, and use the runner's Xcode Swift for macOS tests when the downloaded toolchain and Xcode XCTest frameworks do not match.
