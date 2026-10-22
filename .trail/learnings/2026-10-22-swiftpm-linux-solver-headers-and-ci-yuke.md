---
title: SwiftPM Linux solver headers and CI
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
touches:
  - Package.swift
  - ".github/workflows/ci.yml"
---

## Decided
The SwiftPM Linux failure came from the pinned simple-2d-constraint-solver submodule calling memset and memcpy without including string.h. Keep the parent package buildable by pre-including string.h for its C++ target, and run Swift build/test on Ubuntu plus macOS while initializing only the solver submodule.

## Tried and ruled out
The upstream solver master branch is seven commits ahead of the pinned revision, but does not modify matrix.cpp or otherwise declare the C string functions. Updating the submodule to that revision would not fix this compiler failure.

## Watch out
A macOS-only Swift test run does not cover this Linux compiler error. The local sandbox has no Docker, so the Ubuntu workflow leg is necessary to verify the platform-specific failure after publishing the change.
