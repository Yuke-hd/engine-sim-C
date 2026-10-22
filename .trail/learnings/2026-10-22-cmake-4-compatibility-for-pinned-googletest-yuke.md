---
title: CMake 4 compatibility for pinned GoogleTest
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
touches:
  - ".github/workflows/ci.yml"
  - ".github/workflows/cmake.yml"
---

## Decided
When the hosted runner's CMake 4 rejects the pinned GoogleTest project's `cmake_minimum_required` below 3.5, pass `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` to the CI configure command. This lets the older third-party project configure under the newer runner without changing its pinned source.

## Tried and ruled out
The failure occurred while configuring fetched GoogleTest, before this repository's targets were generated. Changing the top-level project's own minimum version would not update that fetched project's declaration.

## Watch out
`CMAKE_POLICY_VERSION_MINIMUM` was added in CMake 4.0 and is intended as an external compatibility setting for projects that have not updated their own policy version. Revisit the workaround if the pinned GoogleTest source or hosted CMake version changes.
