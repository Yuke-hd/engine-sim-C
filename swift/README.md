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
handle before creating a replacement profile. Both profile ports and embedded
impulse responses retain the upstream MIT notice in `LICENSE`.

`F136V8Tests` checks creation, limits, LS/F136 replacement and cleanup, and
offline output at 3000 and 6000 RPM.

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
