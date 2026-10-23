# EngineSim Swift package

The repository root [`Package.swift`](../Package.swift) builds reusable engine simulation and mono audio synthesis without the upstream UI or script runtime. The package has no dependency on a host app's telemetry, session, or UI types.

| Product | Target | Public surface |
| --- | --- | --- |
| `EngineSim` | `EngineSimCore` | Convenience library name for the C API |
| `EngineSimCore` | `EngineSimCore` | Opaque C handle and controls in [`EngineSimCore.h`](include/EngineSimCore.h) |
| `EngineSound` | `EngineSound`, `EngineSoundRing` | Swift [`EngineSoundSource`](../Sources/EngineSound/EngineSoundSource.swift) protocol, [`EngineSoundPlayer`](../Sources/EngineSound/EngineSoundPlayer.swift), and `ToneSource`; `EngineSoundRing` is its internal C ring target |

`EngineSimCore` compiles the selected `src/` simulator and synthesizer files, the pinned `simple-2d-constraint-solver` source, and the C++ bridge in `swift/`. The bridge creates one of two engine profiles, drives physics on the calling thread, and reads audio from a native synthesizer thread. The `EngineSound` target supplies a player and neutral source protocol. It does not wrap the C handle: a host source owns that adapter. Tests are in `swift/Tests/EngineSimCoreTests`, `swift/Tests/EngineSoundTests`, and `swift/Tests/EngineSoundProfileTests`.

## Build and integrate

Use Swift 5.9 or newer, a C++17 capable Apple toolchain, and macOS 14+ or iOS 17+. From the repository root:

```sh
git submodule update --init dependencies/submodules/simple-2d-constraint-solver
swift test
```

Add the checkout as a local Swift package (or a Git submodule) and link the `EngineSim`/`EngineSimCore` product for the C API; link `EngineSound` for playback or its Swift source protocol. `Package.swift` uses the C++ compiler flag `-fdelayed-template-parsing`, so SwiftPM cannot use this package as a versioned remote dependency. The other repository submodules are not needed by these targets. The normal `swift test` run skips the 40-second render benchmark; set `ENGINE_SIM_BENCHMARK=1` to opt in. The SwiftPM iPhone benchmark is skipped; use the signed device host below for the physical result.

`bash swift/Tests/check_convolution_filter.sh` is not part of `swift test`; run
it after changing `src/convolution_filter.cpp`. It builds
`swift/Tests/ConvolutionFilter/main.cpp` with clang++ and checks
`ConvolutionFilter::f` for impulse-response lengths from 1 to 10000 at every
ring offset. On the native build (NEON on arm64) the largest error against a
double-precision reference must be at most 1e-5 of the output RMS. On Apple silicon with Rosetta it also builds x86_64, where the
scalar fallback must match the original float loop bit for bit.

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

## C API

`EngineSimProfile` values are stable neutral identifiers:

| ID | Constant | Profile | Target RPM range |
| ---: | --- | --- | ---: |
| 0 | `ENGINE_SIM_PROFILE_LS_V8` | GM LS V8 | 0–8000 |
| 1 | `ENGINE_SIM_PROFILE_F136_V8` | Ferrari F136 V8 | 0–9000 |

Ask `engine_sim_profile_min_rpm` and `engine_sim_profile_max_rpm` for bounds instead of hard coding them in a host. Both return 0 for an unknown profile. The range is the dyno **target** range, not a promise that the physical engine will reach it. `engine_sim_rpm` reports the simulated crankshaft's actual RPM. The LS profile's 8000 RPM API cap is distinct from its 6500 RPM redline.

```c
#include "EngineSimCore.h"
#include <stdint.h>
#include <stddef.h>

EngineSimCore *core = engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0);
if (core == NULL) { /* report initialization failure */ }
else {
    double maxRpm = engine_sim_profile_max_rpm(engine_sim_profile(core));
    int physicsHz = engine_sim_simulation_frequency(core);
    int16_t samples[735]; /* 1/60 second of mono PCM16 at 44,100 Hz */

    engine_sim_set_target_rpm(core, 3000.0);
    engine_sim_set_throttle(core, 0.5);
    engine_sim_set_ignition(core, 1);
    int written = engine_sim_render(core, samples, 735);
    if (written != 735) { /* handle a short render or timeout */ }
    (void)maxRpm;
    (void)physicsHz;
    engine_sim_destroy(core);
}
```

`engine_sim_create_ls_v8(frequency)` is the LS convenience constructor. `engine_sim_hold_rpm(core, rpm)` is a legacy shortcut that enables ignition, sets throttle to 0.5, and sets the dyno target. Use the independent setters when the host supplies separate controls:

- `engine_sim_set_target_rpm` enables dyno hold and clamps finite RPM to the selected profile's range. It does not change throttle or ignition.
- `engine_sim_set_throttle` clamps finite values to 0…1. It does not change RPM or ignition.
- `engine_sim_set_ignition` accepts zero as off and any nonzero value as on. New handles start with ignition off. Off immediately zeros returned audio, including audio that was already queued.

Nonfinite RPM/throttle values are ignored. `engine_sim_create` returns null for an unknown profile or initialization failure. A nonpositive frequency selects the profile default of 10,000 physics steps per second; a positive value overrides it. `engine_sim_simulation_frequency` reports the selected value (0 for a null handle). `engine_sim_profile` returns −1 for a null handle, and `engine_sim_rpm` returns 0. `engine_sim_render` returns the count actually written, which can be short on timeout; null handle/buffer or a nonpositive sample count returns 0. Audio is mono signed 16-bit PCM at 44,100 Hz. `engine_sim_render_synchronous` is a slower diagnostic variant; request at least 735 samples per call.

## Supplying fresh inputs

The host decides whether its latest RPM and throttle readings are fresh. For each producer update, pass the latest **finite** values through the independent setters. If the source becomes stale or unavailable, apply the host's neutral policy explicitly, for example target RPM 0, throttle 0, and ignition off. The package has no clock, freshness rule, or automatic stale-input timeout. It reports the profile bounds, actual RPM, simulation frequency, and render count so the host can show status or detect a short render without importing any app-specific types.

```swift
import EngineSimCore
import EngineSound
import Foundation

// The player renders on its own worker thread. This adapter serializes native
// controls, rendering, and destruction, and owns the handle for its lifetime.
final class LockedEngineSource: EngineSoundSource {
    let sampleRate = 44_100.0
    private let lock = NSLock()
    private let core: OpaquePointer

    init?(profile: EngineSimProfile) {
        guard let core = engine_sim_create(profile, 0) else { return nil }
        self.core = core
    }

    deinit { engine_sim_destroy(core) }

    func update(rpm: Double, throttle: Double, ignition: Bool) {
        lock.lock()
        defer { lock.unlock() }
        engine_sim_set_target_rpm(core, rpm)
        engine_sim_set_throttle(core, throttle)
        engine_sim_set_ignition(core, ignition ? 1 : 0)
    }

    func setTargetRPM(_ rpm: Double) {
        lock.lock(); defer { lock.unlock() }
        engine_sim_set_target_rpm(core, rpm)
    }
    func setThrottle(_ throttle: Double) {
        lock.lock(); defer { lock.unlock() }
        engine_sim_set_throttle(core, throttle)
    }
    func setIgnition(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        engine_sim_set_ignition(core, enabled ? 1 : 0)
    }
    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int {
        lock.lock(); defer { lock.unlock() }
        return Int(engine_sim_render(core, frames.baseAddress, Int32(frames.count)))
    }
}

func applyFreshInputs(to source: LockedEngineSource, rpm: Double?, throttle: Double?) {
    if let rpm, let throttle, rpm.isFinite, throttle.isFinite {
        source.update(rpm: rpm, throttle: throttle, ignition: true)
    } else {
        source.update(rpm: 0, throttle: 0, ignition: false)
    }
}
```

Create the source, apply initial inputs, then call `try player.start(source)`.
The player retains it while active. A later `applyFreshInputs` call can arrive
from another thread because this adapter uses the same lock as `render(into:)`.
The host still owns the freshness decision and should treat a short render
as a failure to supply a full buffer.

Serialize all operations on each C handle, including control, render, and
destroy. Rendering runs physics and can block while audio is synthesized;
never invoke it in a real-time audio callback. Destruction joins the native
synthesizer thread. A source that owns a handle must outlive every render call.

### Playback ownership

`EngineSoundPlayer.start(_:policy:)` starts a worker that renders mono PCM16
from the source into a ring buffer; the device audio callback only drains the
ring. The default iOS session policy ducks other audio; `.mixWithOthers` is
also available. `underrunCount` and `consumedFrameCount` report playback
status. `start` can fail on an invalid sample rate, allocation, or audio engine
startup; `switchSource(to:)` requires the same sample rate as the active source.

`switchSource(to:)` crossfades over 20 ms. The player retains both the old
source and its core until the fade completes, even if the caller drops its
reference. `stop()` ends the worker before releasing its source. Let source
ownership destroy the core after the player has finished; do not separately
call `engine_sim_destroy` while the player may still render it.

The player does not serialize a host's control calls with its worker's
`render(into:)` calls. A core-backed source must use one shared lock for
control, render, and teardown, as in the example, or route all calls onto
the same producer thread. Calling the C setters on a live source from an
unsynchronized telemetry callback races the worker. Prepare replacement
sources before switching them into the player.

## Source and licenses

[`NOTICE`](../NOTICE) records the pinned upstream engine-sim and solver revisions, the source and sound assets used by this package, local changes, and their MIT license notices. The root [`LICENSE`](../LICENSE) retains the engine-sim notice. A distribution containing the package must carry both notices.
