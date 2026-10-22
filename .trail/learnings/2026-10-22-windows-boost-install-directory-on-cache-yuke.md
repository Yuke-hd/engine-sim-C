---
title: Windows Boost install directory on cache miss
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
touches:
  - ".github/workflows/cmake.yml"
---

## Decided
When using `MarkusJx/install-boost@v2.3.0` with an explicit `boost_install_dir`, create that directory before invoking the action on a cache miss. The action creates a nested Boost directory and can fail with ENOENT if the custom parent does not exist.

## Tried and ruled out
The deprecated `actions/cache@v2` was the first CMake workflow failure, but upgrading it only exposed the separate missing-parent-directory error in the Boost installation step.

## Watch out
`actions/cache` does not guarantee that a missing cache path exists after a cache miss. Keep the directory preparation conditional on the cache miss and before the installer. The action's `BOOST_ROOT` output remains the source for the CMake environment.
