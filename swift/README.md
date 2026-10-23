# EngineSim Swift package

The repository root [`Package.swift`](../Package.swift) builds reusable engine simulation and mono audio synthesis without the upstream UI or script runtime. The package has no dependency on a host app's telemetry, session, or UI types.

| Product | Target | Public surface |
| --- | --- | --- |
| `EngineSim` | `EngineSimCore` | Convenience library name for the C API |
| `EngineSimCore` | `EngineSimCore` | Opaque C handle and controls in [`EngineSimCore.h`](include/EngineSimCore.h) |
| `EngineSound` | `EngineSound`, `EngineSoundRing` | Swift [`EngineSoundSource`](../Sources/EngineSound/EngineSoundSource.swift) protocol, [`EngineSoundPlayer`](../Sources/EngineSound/EngineSoundPlayer.swift) with `AudioSessionMixPolicy` and `EngineSoundPlayerError`, the injectable [`EngineSoundSession`](../Sources/EngineSound/EngineSoundSession.swift) with its iOS `IOSAudioSession` adapter and thermal types, [`RPMFollower`](../Sources/EngineSound/RPMFollower.swift), [`ToneSource`](../Sources/EngineSound/ToneSource.swift), and the single-producer/single-consumer [`RingBuffer`](../Sources/EngineSound/RingBuffer.swift); `EngineSoundRing` is its internal C ring target |

`EngineSimCore` compiles the selected `src/` simulator and synthesizer files, the pinned `simple-2d-constraint-solver` source, and the C++ bridge in `swift/`. The bridge creates one of two engine profiles, drives physics on the calling thread, and reads audio from a native synthesizer thread. The `EngineSound` target supplies a player and neutral source protocol. It does not wrap the C handle: a host source owns that adapter. The player's internal [`CrossfadeMixer`](../Sources/EngineSound/CrossfadeMixer.swift) applies its fades and output headroom. [`BRIDGE.md`](BRIDGE.md) records the bridge's native lifecycle fixes and firing-order decisions.

## Build and integrate

Use Swift 5.9 or newer, a C++17 capable Apple toolchain, and macOS 14+ or iOS 17+. From the repository root:

```sh
git submodule update --init dependencies/submodules/simple-2d-constraint-solver
swift test
```

Add the checkout as a local Swift package (or a Git submodule) and link the `EngineSim`/`EngineSimCore` product for the C API; link `EngineSound` for playback or its Swift source protocol. `Package.swift` uses the C++ compiler flag `-fdelayed-template-parsing`, so SwiftPM cannot use this package as a versioned remote dependency. The other repository submodules are not needed by these targets.

## Tests

`swift test` runs three test targets:

- `swift/Tests/EngineSimCoreTests`: C API controls, bounds and invalid handles (`ControlAPITests`), LS rendering at a held 3000 RPM (`LsV8RenderTests`), and F136 creation, bounds, LS/F136 replacement, cleanup and firing-order output at 3000 and 6000 RPM (`F136V8Tests`). The 40-second real-time-factor benchmark is skipped unless `ENGINE_SIM_BENCHMARK` is set in the test process environment; any value, including `0` or an empty string, runs it.
- `swift/Tests/EngineSoundTests`: ring buffer ordering, underrun and overrun behavior, and rejection of an extreme finite sample rate by `EngineSoundPlayer.start` (`PlaybackTests.testExtremeFiniteSampleRateIsRejected`), and `RPMFollowerTests` (interpolation, clamping, stale/disconnected fades, age expiry and derived throttle) on every platform; `ToneSource` playback, source switching, shared session policy, a 60-second underrun check, and `SessionTests` (interruption, route-change, thermal and playback-failure handling through an injected session) only on iOS.
- `swift/Tests/EngineSoundProfileTests`: `testLsToF136CrossfadeHasNoClick` feeds offline LS and F136 renders through the player's cross-fade mixer at the splice with the largest level jump, and bounds every output step to what a linear 20 ms fade can add to the sources' own steps; an abrupt switch fails that bound. `testPlayerCrossfadesFromLsToF136AndReleasesOldCore` switches a live `EngineSoundPlayer` between sources that retain their cores and checks audio consumption, underruns, non-silent sources and release of the old core. It runs only on an iOS Simulator.

On macOS, the iOS-only tests report as skipped. Run them on a Simulator with:

```sh
xcrun simctl list devices available
xcodebuild test -scheme EngineSim-Package \
  -destination 'platform=iOS Simulator,id=<available-device-id>' CODE_SIGNING_ALLOWED=NO
```

`bash swift/Tests/check_bridge_leaks.sh` (macOS) builds the standalone `BridgeLifecycle` and `ThreadStartFailure` probes against the package objects and runs `leaks --atExit` on them. Neither SwiftPM nor the Simulator measures physical render throughput; use the device benchmark below.

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

Recorded on iPhone 12 Pro, iOS 26.0.1, Release: a cool (nominal) start measured
LS median 0.633 and F136 median 0.629 (PASS), and a later run measured
LS 0.636 and F136 0.665. A warm F136 median is about 0.70, which fails the
strict bound, so compare only cool starts. At 10 kHz the synthesizer's
convolution is no longer the critical path: `ConvolutionFilter::f` in
`src/convolution_filter.cpp` uses a NEON dot product on arm64 (other targets
keep the original scalar loop; see `check_convolution_filter.sh` above), and the
physics thread now dominates. Physics optimization is tracked in issue #16.

### Device demo

The app's **Listen** section plays the LS V8 or F136 V8 live through the device
speaker with `EngineSoundPlayer`. Pick an idle RPM (1000, 2000 or 3000) and an
engine; switching either cross-fades to a new core. While playing, the throttle
slider (0-1) drives `engine_sim_set_throttle` and moves the dyno-held RPM from
idle toward 6500 RPM at up to 3000 RPM/s, without re-creating the core. The
slider value is applied inside the source's `render(into:)` on the player's
worker thread, so the main thread never calls into the core. Live playback
simulates at 4000 Hz. That is a demo choice, not the package default (10 kHz,
selected by passing 0 to `engine_sim_create`) or the gate setting; see the
limitation below. For headless runs through
`xcrun devicectl device process launch --console`, set
`DEVICECTL_CHILD_BENCHMARK_AUTORUN=1` to run the benchmark at launch, or
`DEVICECTL_CHILD_LISTEN_SELFTEST=1` to sweep the throttle on each engine; both
print to the console. If both are set, only the benchmark runs and the app
prints that the self-test was skipped.

### Minimum validated simulation frequency

**4000 Hz is the lowest validated rate** for both profiles over 1000–6500 RPM,
throttle 0, 0.1 and 1, and ramp/snap throttle sweeps. Treat it as the minimum
for that tested range; it is not a guarantee for other profiles or operating
conditions. The production default remains **10,000 Hz**.

### Known limitation: 1000-2000 Hz simulation

At 1000-2000 Hz the cylinder force in `CombustionChamber::apply` can become
NaN or infinite and stop on `assert(false)` at `src/combustion_chamber.cpp:417`.
At 1000 Hz this happens at 1000 RPM for both profiles, at 6000 and 7500 RPM for
LS and at 8500 RPM for F136, and with low throttle at many other RPMs. At
2000 Hz it still happens at 5000-6500 RPM with low throttle. 4000 Hz passed
every tested combination (1000-6500 RPM, throttle 0, 0.1 and 1, and ramp and
snap throttle sweeps). Debug builds assert on the invalid force. Release builds
define `NDEBUG` and explicitly reject nonfinite pressure/friction forces before
they reach the solver. Rejection does not repair the underlying unstable gas
state or make low-frequency playback safe; keep to the validated range. This
upstream stability limitation is tracked in #16. The benchmark's
1000 Hz reference lines and `EngineSoundProfileTests` use 1000 Hz only at
3000 RPM. Keep the default 10 kHz (pass 0) unless a lower rate has been checked
over the RPMs and throttles the host will request.

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

The host decides whether its latest RPM and throttle readings are fresh. For each producer update, pass the latest **finite** values through the independent setters. If the source becomes stale or unavailable, apply the host's neutral policy explicitly, for example target RPM 0, throttle 0, and ignition off. The player and C API have no clock, freshness rule, or automatic stale-input timeout; the optional `RPMFollower` (below) applies one only when the host feeds it timestamped readings. The package reports the profile bounds, actual RPM, simulation frequency, and render count so the host can show status or detect a short render without importing any app-specific types.

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

`EngineSoundPlayer.start(_:policy:)` stops any current playback, then starts a
producer thread that renders 256-frame blocks of mono PCM16 from the source
into an 8192-frame ring buffer. It prebuffers 2048 frames before connecting
the device; the audio callback only drains the ring and copies each sample to
both output channels. The default policy, `.duckOthers`, ducks other audio on
iOS; `.mixWithOthers` mixes with it. Players in one process share the
`AVAudioSession`: it stays active, and ducks while any active player asked to
duck, until the last player stops. On macOS the policy is ignored.

The producer fades output in over 20 ms on start and out over 20 ms on `stop()`,
and scales every sample by 0.8 for headroom. A short or negative
`render(into:)` result is padded with silence; the player does not report it.
`underrunCount` and `consumedFrameCount` report the ring's playback status.

`start` throws `EngineSoundPlayerError.invalidSampleRate` unless the source's
`sampleRate` is finite and within 8,000…192,000 Hz, and `.allocationFailed`
if the ring cannot be allocated. It rethrows `AVAudioSession` errors on iOS and
`AVAudioEngine.start()` errors after releasing the session. `switchSource(to:)`
throws `.incompatibleSampleRate` unless the new source has the active source's
sample rate; with no active playback it calls `start` with the default policy.

`switchSource(to:)` crossfades linearly over 20 ms. The player retains both the old
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

### Session, route and thermal handling

`EngineSoundPlayer(session:)` takes an optional `EngineSoundSession`; on iOS
the default `IOSAudioSession` configures the shared playback session and
reports interruptions, output route changes (`EngineSoundRouteChangeReason`)
and thermal state (`EngineSoundThermalState`). Removing headphones, Bluetooth
or CarPlay pauses playback until the host calls `start` again. Thermal
`.serious` asks an `EngineSoundThermalControllable` source, on the producer
thread, for half the simulation frequency; `.critical` stops playback until it
improves. Automatic resume failures are reported through `lastPlaybackFailure`
and `onPlaybackFailure` (called on the main queue). [`BRIDGE.md`](BRIDGE.md)
documents the full lifecycle rules.

## Following live RPM

`RPMFollower` turns timestamped `RPMFollowerInput` readings (RPM,
`RPMFreshness`, age, accelerator throttle, sample time) into
`RPMFollowerOutput` target RPM, throttle and gain for one playback instant.
Create it with the profile's RPM range, feed readings with `update(_:)`, and
evaluate it with `output(at:)` on the same monotonic clock. A new reading
interpolates over `interpolationDuration` (0.1 s by default). An invalid,
stale or disconnected reading, or one older than `maxReadingAge` (0.5 s by
default), resets the target to the profile minimum and fades gain to silence
over `fadeDuration` (0.2 s). When no accelerator throttle is supplied, throttle
is derived from the RPM rate (`isThrottleDerived`). The host applies the
output to its source and its own gain stage.

## Source and licenses

[`NOTICE`](../NOTICE) records the pinned upstream engine-sim and solver revisions, the source and sound assets used by this package, local changes, and their MIT license notices. The root [`LICENSE`](../LICENSE) retains the engine-sim notice. A distribution containing the package must carry both notices.

## Physics performance comparison (#16)

Release builds compile the native core and solver with `-O3 -flto=thin`, allowing
physics calls to inline across translation units. IEEE floating-point
arithmetic remains enabled without fast-math. Release also defines `NDEBUG`
to remove solver bounds assertions; `CombustionChamber::apply` explicitly rejects
nonfinite pressure and projected forces before touching solver state. Debug
assertions stay enabled. Solver tolerance, fluid substep count, default frequency,
and public API remain unchanged. Run `bash swift/Tests/check_force_guard.sh`
to verify injected NaN and positive/negative infinity against the Release core.

For host diagnostics, run one revision at a time with no other builds or tests.
For the `2517ebf` reference checkout, copy the candidate’s
`swift/Benchmarks/PhysicsCost/` directory into the same location in that checkout
(the harness did not exist there), initialize its solver submodule, and keep its
`Package.swift` and engine sources unchanged. Use separate output prefixes:

```sh
bash swift/Benchmarks/PhysicsCost/run.sh /tmp/reference > /tmp/reference.txt
# Repeat on the candidate revision, using /tmp/candidate as the prefix.
python3 swift/Benchmarks/PhysicsCost/compare.py /tmp/reference /tmp/candidate
```

The comparison script requires NumPy in the invoking Python environment. The
native probe reports five timed 3 s renders per profile at the default 10 kHz,
3000 RPM, after 0.5 s settling and a discarded 3 s warm-up. It also saves two
seconds of mono PCM16 after two seconds settling for both profiles at
1500/3000/5000 RPM and throttle 0/0.5/1. `--timing-only` omits the PCM sweep.
Comparison uses the final 65,536 samples with a Hann window (0.673 Hz bins),
reports firing-order peaks in ±10% of RPM/15 and dominant peaks over 40–600 Hz,
plus whole-render RMS, sample peak and clipping counts. The regression tolerance
is firing peaks within 3% of expected, dominant peaks within one FFT bin between
revisions, RMS within 1%, and complete, non-silent, unclipped output. PCM bytes
can differ because synthesizer scheduling changes the render alignment.

Physical acceptance still requires the signed benchmark app above. Build and
run the same Release revision on an iPhone, cool the device to nominal thermal
state, then tap **Run LS and F136 benchmark**. Save the complete report. Run
again after sustained engine playback has warmed the device; record whether the
start is nominal/fair/serious, ambient conditions and whether connected to power.
Record LS and F136 min/median/max for both starts and repeat on the reference
revision using the same phone and conditions. Keep the existing #6 `<0.7` gate;
#16's proposed F136 cool `≤0.5` / warm `<0.7` targets require owner confirmation.
Host and Simulator timings do not establish physical acceptance.
