# Swift sound source

`EngineSound` exports the neutral `EngineSoundSource` protocol as a prerequisite
slice for playback issue #2. Companion owns its `EngineSimSource` adapter; this
package does not depend on Companion. `EngineSimCore` exports an opaque C handle,
profile selection and independent RPM/throttle/ignition controls. New instances
are silent until ignition is enabled. Invalid nonfinite controls are ignored;
finite controls are clamped to RPM 0...8000 and throttle 0...1. PCM output is mono
signed 16-bit at 44,100 Hz. `engine_sim_create_ls_v8` and `engine_sim_hold_rpm`
remain available for existing clients.

Serialize creation, controls, rendering and destruction on the producer thread.
Rendering simulates physics and waits for synthesized output, so it must not run
inside an audio callback. The owner should retain the source until all producer
work has stopped; destruction joins the native synthesizer thread.

The source does not know about BLE, freshness, sessions or playback. The caller
must stop supplying stale telemetry and apply the player fade/silence policy.
Disabling ignition immediately zeros output, including previously buffered audio.

Native lifecycle fixes free synthesizer transfer buffers, jitter histories,
cylinder heads, rod journal arrays, displacement scratch arrays, crankshaft
links, and the optimized solver. The solver API borrows its solver pointer;
`OwnedOptimizedSystem` keeps that ownership local without changing the solver
submodule.

## Verification

Run `swift test` and `xcodebuild test -scheme EngineSim-Package -destination
'platform=iOS Simulator,id=<available-device-id>' CODE_SIGNING_ALLOWED=NO`.
Use `xcrun simctl list devices available` to select the simulator.

On macOS, `bash swift/Tests/check_bridge_leaks.sh` builds a standalone native
probe and runs `leaks --atExit` over 40 create/control/render/destroy cycles.
The probe avoids XCTest's framework allocations. The initial check found
920 leaks totaling 15,408,640 bytes; after the ownership fixes it reports
0 leaks and 0 leaked bytes.

## Firing order and the original sound

The owner chose the original sound after listening to matched native/filtered
clips: the filtered version no longer sounded like an engine. Preserve the
physical simulator output; do not add a tone or track a narrow output filter to
make the expected firing frequency globally loudest.

At 1500/3000/5000 RPM the raw LS V8's strongest measured lower-band peaks are
62.5/200/125 Hz. Actual crank speed matches the requested RPM. The fourth crank
order (100/200/333.3 Hz) is present, but the cross-plane exhaust and impulse
response can make lower orders stronger. The regression therefore checks the
local firing-order frequency within 3%, separating it from adjacent half-orders,
and separately verifies actual crank RPM within 2%. It does not claim that the
firing order is the strongest sound component. This replaces the original
loudest-firing-component requirement following the owner's listening decision.
