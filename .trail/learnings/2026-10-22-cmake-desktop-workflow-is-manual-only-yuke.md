---
title: CMake desktop workflow is manual-only
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
cost: { minutes: 2, tokens: 8225 }
touches:
  - ".github/workflows/cmake.yml"
---

## Decided
The owner does not need the Windows desktop app (`engine-sim-app` is a WIN32 executable and delta-studio renders with Direct3D 11), so `.github/workflows/cmake.yml` runs only on `workflow_dispatch` and is not part of PR or push CI. CI coverage for this fork is the SwiftPM matrix in `ci.yml`. The Boost, CMake-policy and SDL2 fixes attempted on PR #13 were dropped; cmake.yml otherwise matches upstream.

## Tried and ruled out
Moving the CMake build to Linux or macOS: the app and its renderer are Windows-only. Keeping it on PRs: every fix (Boost install, CMake 4 policy minimum, SDL2) uncovered another Windows-only failure, and it had never passed on this fork.

## Watch out
If the desktop build is ever revived, the earlier CMake/Boost learnings from 2026-10-22 describe the fixes needed; do not re-add PR/push triggers without the owner asking.
