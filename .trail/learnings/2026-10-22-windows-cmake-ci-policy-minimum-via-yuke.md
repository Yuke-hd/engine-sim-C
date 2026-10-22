---
title: "Windows CMake CI: policy minimum via env and SDL2 from vcpkg"
author: Yuke-hd
date: 2026-10-22
branch: codex/ci-linux-build
cost: { minutes: 1, tokens: 52789 }
touches:
  - ".github/workflows/cmake.yml"
---

## Decided
The CMake workflow runs on windows-latest with PowerShell, which splits an unquoted `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` at the dot so CMake sees "3" and rejects it. Set `CMAKE_POLICY_VERSION_MINIMUM: 3.5` in the configure step's `env:` instead (CMake 4 reads it from the environment). This supersedes the earlier advice to pass it as a `-D` flag.

delta-studio does `find_package(SDL2 REQUIRED)` and `find_package(SDL2_image REQUIRED)` through its own find modules, which honour `ENV SDL2DIR`. Install both with the runner's preinstalled vcpkg (`vcpkg install sdl2 sdl2-image --triplet x64-windows`) and set `SDL2DIR` to `$env:VCPKG_INSTALLATION_ROOT/installed/x64-windows` inside the PowerShell run block.

## Watch out
Runner-provided variables such as `VCPKG_INSTALLATION_ROOT` are not in the `${{ env.* }}` expression context; read them from the shell (`$env:...`). The CMake workflow had never passed on this fork before these fixes, so expect further Windows-only build failures after configure succeeds.
