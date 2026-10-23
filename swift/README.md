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
3. Select the Release build configuration for the Run action, then Build and
   Run. Tap **Run LS and F136 benchmark** and wait for the result on screen
   (about a minute).
4. Copy the complete result text, including device, iOS version, build
   configuration, simulation frequency, sample rate, per-run ratios, min/median/max,
   and PASS or FAIL, into issue #6 or PR #10. Confirm the device model is iPhone 12 Pro in iOS
   Settings because the app displays the user-assigned device name.

For the LS V8 baseline and then the F136 V8, the app holds 3000 RPM at the
production default simulation frequency (`ENGINE_SIM_DEFAULT_FREQUENCY`, 10 kHz)
and 44.1 kHz mono PCM16 output, settles for 0.5 seconds, discards one 3-second
warm-up render, and times five 3-second offline renders. It reports each
compute/audio ratio (wall-clock compute duration divided by rendered audio
duration) with the min, median and max. The gate is on the F136 median: it
passes only when every timed F136 buffer is complete, non-silent and unclipped
and the median ratio is strictly below 0.7. Each result prints the frequency the
core reports (`engine_sim_simulation_frequency`), and the gate also requires the
F136 core to report the 10 kHz default. The max is shown but not gated, and
the LS result is informational. The margin at 10 kHz is thin and device heat
raises the ratios by about 0.06, so the report prints `ProcessInfo` thermal state
before and after the gate runs and says whether it was a cool (nominal) or warm
start. After the gate, the app prints 1000 Hz and 4000 Hz min/median/max for both
engines as reference lines only; they are not gated. Only 3000 RPM is measured:
at 1000 Hz simulation, 1000 RPM, and 6000/7500 RPM (LS) or 8500 RPM (F136), trip
the `combustion_chamber.cpp` assertion. A Simulator
run can check that the app builds, but only the signed physical-iPhone result
satisfies this acceptance gate.

The app's **Listen** section plays the LS V8 or F136 V8 live through the device
speaker with `EngineSoundPlayer`. Pick an idle RPM (1000, 2000 or 3000) and an
engine; switching either cross-fades to a new core. While playing, the throttle
slider (0-1) drives `engine_sim_set_throttle` and moves the dyno-held RPM from
idle toward 6500 RPM at up to 3000 RPM/s, without re-creating the core. Live
playback simulates at 4000 Hz, a demo choice rather than the 10 kHz gate
setting: at 1000-2000 Hz low throttle and many RPMs trip the
`combustion_chamber.cpp` assertion, which is compiled into Release builds. For headless runs through
`xcrun devicectl device process launch --console`, set
`DEVICECTL_CHILD_BENCHMARK_AUTORUN=1` to run the benchmark at launch, or
`DEVICECTL_CHILD_LISTEN_SELFTEST=1` to sweep the throttle on each engine; both
print to the console. If both are set, only the benchmark runs and the app
prints that the self-test was skipped.

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
