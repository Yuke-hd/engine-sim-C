# Swift package and C API

`Package.swift` at the repository root builds the simulation and synthesizer core
(`src/*.cpp` minus UI, scripting and delta-studio, plus
`simple-2d-constraint-solver`) as the `EngineSimCore` library, together with:

- `swift/include/EngineSimCore.h`: C API (create / destroy / hold RPM / render / RPM).
- `swift/ls_v8_builder.cpp`: C++ hand port of `assets/engines/atg-video-2/07_gm_ls.mr`
  (the Piranha scripting layer is not built).
- `swift/ls_v8_impulse_response.cpp`: `assets/sound-library/smooth/smooth_39.wav`
  embedded as bytes, read by `swift/wav_reader.cpp`.
- `swift/f136_v8_builder.cpp`: C++ hand port of
  `assets/engines/atg-video-2/08_ferrari_f136_v8.mr`.
- `swift/f136_v8_impulse_response.cpp`: the profile's
  `es/sound-library/new/mild_exhaust_reverb.wav` embedded as bytes.
- `swift/Tests`: host test (2 s render at a 3000 RPM dyno hold) and real-time benchmark.

Only the solver submodule is needed:

    git submodule update --init dependencies/submodules/simple-2d-constraint-solver
    swift test

The package uses `unsafeFlags` (`-fdelayed-template-parsing`), so consume it by path or
submodule, not as a versioned remote dependency. The benchmark test is skipped unless
`ENGINE_SIM_BENCHMARK=1` is set.

Create the F136 profile with `engine_sim_create(ENGINE_SIM_PROFILE_F136_V8,
simulationFrequency)`. Its stable neutral profile ID is `1`. Query the
valid target range with `engine_sim_profile_min_rpm` and
`engine_sim_profile_max_rpm` (0 to 9000 RPM for F136). Destroy the previous
handle when direct C API playback no longer uses it. For an
`EngineSoundPlayer` source switch, create the new core-owning source and call
`switchSource(to:)`; the player retains the old source and its core until the
cross-fade finishes, even after the caller releases its reference. Do not
destroy that core while the player may render from it. Both profile ports and
embedded impulse responses retain the upstream MIT notice in `LICENSE`.

`F136V8Tests` checks creation, limits, LS/F136 replacement and cleanup, and
offline output at 3000 and 6000 RPM. `EngineSoundProfileTests` feeds offline LS
and F136 renders through the player's cross-fade mixer at the splice with the
largest level jump, and bounds every output step to what a linear 20 ms fade
can add to the sources' own steps; an abrupt switch fails that bound. It also
switches a live `EngineSoundPlayer` between sources that retain their
respective cores. On iOS Simulator it checks audio consumption, underruns,
non-silent sources, and release of the old core after the fade.
Physical render throughput is measured by the device benchmark below.

## Physical iPhone F136 benchmark

The benchmark is an iOS host app in
`swift/Benchmarks/F136DeviceBenchmark/F136DeviceBenchmark.xcodeproj`. A SwiftPM
XCTest bundle cannot run directly on a physical iPhone without an app host.
To collect the issue #6 result on a signed iPhone 12 Pro:

1. Open the project in Xcode and select the `F136DeviceBenchmark` scheme.
2. In **Signing & Capabilities**, select your development team and set a unique
   bundle identifier if Xcode requests one. Connect and select the iPhone 12 Pro
   as the run destination.
3. Build and Run. Tap **Run 3-second render** and wait for the result on screen.
4. Copy the complete result text, including device, iOS version, simulation
   frequency, sample rate, frame count, compute/audio ratio, and PASS or FAIL,
   into issue #6 or PR #10. Confirm the device model is iPhone 12 Pro in iOS
   Settings because the app displays the user-assigned device name.

The app warms up for 0.5 seconds, then times one 3-second offline F136 render
at 3000 RPM, 1000 Hz simulation, and 44.1 kHz mono PCM16 output. It passes only
when the full audio buffer is rendered, non-silent and unclipped, and wall-clock
compute duration divided by rendered audio duration is at most 0.5. A Simulator
run can check that the app builds, but only the signed physical-iPhone result
satisfies this acceptance gate.

Changes to upstream files, needed so clang builds them:

- `include/units.h`, `include/constants.h`: `extern constexpr` to `inline constexpr`
  (duplicate symbols across translation units).
- `include/gas_system.h`: user-provided `Mix()` constructor (clang rejects its use as a
  default argument inside `GasSystem`).
- `src/synthesizer.cpp`: drop the unused `delta.h` include.
- `src/piston_engine_simulator.cpp`: drop an assert on the nonexistent `m_antialiasingFilters` member.
- `src/simulator.cpp`, `src/piston_engine_simulator.cpp`: `PistonEngineSimulator::destroy()` now calls `Simulator::destroy()`, and that frees `m_dynoTorqueSamples` (it leaked and tripped the destructor assert).
- `src/engine.cpp`, `src/connecting_rod.cpp`: drop the Windows-style `..\include\...` includes
  that duplicate the forward-slash ones.
