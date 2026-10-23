---
title: PR 11 documentation and inherited F136 check results
author: yk-s-coding-bot
date: 2026-10-22
branch: codex/gh-7-swift-package-docs
touches:
  - swift/README.md
  - swift/Tests/EngineSimCoreTests/F136V8Tests.swift
---

## Decided
- PR #11 changes only package documentation and notices. The new `swift/README.md` product/target table names `EngineSimCore`; it does not change the F136 bank/wire angles, firing order, or source implementation. `trail check` interpreting that prose as a cylinder-mapping change is a false positive.
- The existing `F136V8Tests.testIPhoneRenderBenchmark` remains an explicit `XCTSkip` because physical-device execution requires a host app and matching signing/provisioning. PR #11 neither removes nor reenables that test; `trail check` reports inherited #6 branch content.

## Watch out
- Preserve the F136 mapping and the host/provisioning limitation recorded in the existing F136 source-port learning. Reassess the hardware benchmark only when a signed physical-iPhone host is available.
