# Swift package and C API

`Package.swift` at the repository root builds the simulation and synthesizer core
(`src/*.cpp` minus UI, scripting and delta-studio, plus
`simple-2d-constraint-solver`) as the `EngineSimCore` library, together with:

- `swift/include/EngineSimCore.h`: C API (create / destroy / hold RPM / render / RPM).
- `swift/ls_v8_builder.cpp`: C++ hand port of `assets/engines/atg-video-2/07_gm_ls.mr`
  (the Piranha scripting layer is not built).
- `swift/ls_v8_impulse_response.cpp`: `assets/sound-library/smooth/smooth_39.wav`
  embedded as bytes, read by `swift/wav_reader.cpp`.
- `swift/Tests`: host test (2 s render at a 3000 RPM dyno hold) and real-time benchmark.

Only the solver submodule is needed:

    git submodule update --init dependencies/submodules/simple-2d-constraint-solver
    swift test

Changes to upstream files, needed so clang builds them:

- `include/units.h`, `include/constants.h`: `extern constexpr` to `inline constexpr`
  (duplicate symbols across translation units).
- `include/gas_system.h`: user-provided `Mix()` constructor (clang rejects its use as a
  default argument inside `GasSystem`).
- `src/synthesizer.cpp`: drop the unused `delta.h` include.
- `src/engine.cpp`, `src/connecting_rod.cpp`: drop the Windows-style `..\include\...` includes
  that duplicate the forward-slash ones.
