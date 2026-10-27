#ifndef ENGINE_SIM_CORE_H
#define ENGINE_SIM_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EngineSimCore EngineSimCore;
typedef enum {
    ENGINE_SIM_PROFILE_LS_V8 = 0,
    ENGINE_SIM_PROFILE_F136_V8 = 1,
    ENGINE_SIM_PROFILE_M177_V8 = 2
} EngineSimProfile;

// All operations on a handle must be serialized on a producer thread. Render
// performs physics and may block: never call it in a real-time audio callback.
// Instances start with ignition off. Unknown profiles return null.
EngineSimCore *engine_sim_create(EngineSimProfile profile, int simulationFrequency);

#define ENGINE_SIM_DEFAULT_FREQUENCY 10000
#define ENGINE_SIM_SAMPLE_RATE 44100

/// Builds the GM LS V8 with its exhaust impulse response and starts the audio thread.
/// `simulationFrequency` is the physics rate in Hz; 0 selects the default (10000).
EngineSimCore *engine_sim_create_ls_v8(int simulationFrequency);
/// Returns the neutral profile identifier used to create this handle, or -1 for null.
EngineSimProfile engine_sim_profile(const EngineSimCore *core);
/// Valid target RPM range for a profile; unknown profiles return 0.
double engine_sim_profile_min_rpm(EngineSimProfile profile);
double engine_sim_profile_max_rpm(EngineSimProfile profile);
void engine_sim_destroy(EngineSimCore *core);

#define ENGINE_SIM_LEVELER_PEAK 0
#define ENGINE_SIM_LEVELER_RPM_SCALED 1

/// Selects the output leveler. ENGINE_SIM_LEVELER_PEAK normalizes peaks to a fixed
/// level (the original behaviour, flat loudness across RPM);
/// ENGINE_SIM_LEVELER_RPM_SCALED (the default) levels by RMS to a target that
/// rises with RPM and throttle, so the engine gets louder as it revs and opens.
void engine_sim_set_leveler_mode(EngineSimCore *core, int mode);

/// Enables ignition and the dynamometer and holds the crankshaft at `rpm`.
void engine_sim_hold_rpm(EngineSimCore *core, double rpm);

// Finite RPM is clamped to the selected profile's bounds, throttle to 0...1; nonfinite inputs
// are ignored. Ignition off immediately mutes even previously queued audio.
// Independent producer-thread controls; unlike hold_rpm these do not alter
// one another. The dynamometer holds the requested telemetry RPM.
void engine_sim_set_target_rpm(EngineSimCore *core, double rpm);
void engine_sim_set_throttle(EngineSimCore *core, double throttle);
void engine_sim_set_ignition(EngineSimCore *core, int enabled);

/// Renders `sampleCount` mono 16-bit samples at 44.1 kHz into `out`. Physics
/// runs on the calling thread while the synthesizer renders audio on its own
/// thread, as in a live player. Returns the number of samples written (less
/// than requested only on timeout).
int engine_sim_render(EngineSimCore *core, int16_t *out, int sampleCount);

/// Same output, but waits for the synthesizer after every 1/60 s frame so
/// physics and audio never overlap. Slower; kept for comparison and debugging.
/// Request at least 735 samples (one frame at 44.1 kHz) per call: with smaller
/// requests the synthesizer's output buffer fills and each call waits out a
/// 200 ms timeout.
int engine_sim_render_synchronous(EngineSimCore *core, int16_t *out, int sampleCount);

double engine_sim_rpm(const EngineSimCore *core);
int engine_sim_simulation_frequency(const EngineSimCore *core);

#ifdef __cplusplus
}
#endif

#endif
