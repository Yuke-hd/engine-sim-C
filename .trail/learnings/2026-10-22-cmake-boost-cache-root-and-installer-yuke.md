---
title: CMake Boost cache root and installer outputs
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
touches:
  - ".github/workflows/cmake.yml"
---

## Decided
With `MarkusJx/install-boost@v2.6.0` and `boost_install_dir: ${{github.workspace}}`, cache `${{github.workspace}}/boost` and give CMake `${{github.workspace}}/boost/boost` as `BOOST_ROOT`. Disable the install action's own cache when the workflow already uses `actions/cache`.

## Tried and ruled out
Using `steps.install-boost.outputs.BOOST_ROOT` for CMake is unreliable when the install step is conditional on an outer cache miss: on a cache hit, the step is skipped and has no output. On the 2026-10-22 run, v2.3.0 also downloaded a 54 KB invalid file for a 572 MB Boost archive and failed extraction; use the current installer release and verify the result in CI.

## Watch out
`boost_install_dir` is a parent directory; the action appends its own `boost` paths. Keep the external cache directory and computed `BOOST_ROOT` aligned, and ensure the path works both when the cache hits and when the installer runs.
