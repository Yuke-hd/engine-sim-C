#include "EngineSimCore.h"

#include "ls_v8_builder.h"
#include "ls_v8_impulse_response.h"
#include "f136_v8_builder.h"
#include "f136_v8_impulse_response.h"
#include "m177_v8_builder.h"
#include "wav_reader.h"

#include "engine.h"
#include "exhaust_system.h"
#include "ignition_module.h"
#include "impulse_response.h"
#include "piston_engine_simulator.h"
#include "synthesizer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <thread>

struct EngineSimCore {
    bool ignition = false;
    bool rpmScaledLeveler = false;
    float levelerTarget = 0;
    EngineSimProfile profile = ENGINE_SIM_PROFILE_LS_V8;
    LsV8 ls;
    F136V8 f136;
    M177V8 m177;
    PistonEngineSimulator *simulator = nullptr;
    Engine *engine() const {
        if (profile == ENGINE_SIM_PROFILE_LS_V8) return ls.engine;
        if (profile == ENGINE_SIM_PROFILE_F136_V8) return f136.engine;
        return m177.engine;
    }
    Vehicle *vehicle() const {
        if (profile == ENGINE_SIM_PROFILE_LS_V8) return ls.vehicle;
        if (profile == ENGINE_SIM_PROFILE_F136_V8) return f136.vehicle;
        return m177.vehicle;
    }
    Transmission *transmission() const {
        if (profile == ENGINE_SIM_PROFILE_LS_V8) return ls.transmission;
        if (profile == ENGINE_SIM_PROFILE_F136_V8) return f136.transmission;
        return m177.transmission;
    }
};

namespace {
constexpr double kFrameSeconds = 1.0 / 60.0;
constexpr auto kFrameTimeout = std::chrono::milliseconds(200);

// Blocks until the render thread has consumed this frame's input, so output is
// deterministic. The thread only signals when it had input to process.
void waitForRender(Synthesizer &synth) {
    std::unique_lock<std::mutex> lock(synth.m_lock0);
    synth.m_cv0.wait_for(lock, kFrameTimeout, [&synth] { return synth.m_processed; });
}
}

EngineSimCore *engine_sim_create(EngineSimProfile profile, int simulationFrequency) {
    if (profile != ENGINE_SIM_PROFILE_LS_V8 && profile != ENGINE_SIM_PROFILE_F136_V8
        && profile != ENGINE_SIM_PROFILE_M177_V8) return nullptr;
    try {
    std::unique_ptr<EngineSimCore, decltype(&engine_sim_destroy)> core(new EngineSimCore, engine_sim_destroy);
    core->profile = profile;
    if (profile == ENGINE_SIM_PROFILE_LS_V8) buildLsV8(&core->ls);
    else if (profile == ENGINE_SIM_PROFILE_F136_V8) buildF136V8(&core->f136);
    else buildM177V8(&core->m177);

    Engine *engine = core->engine();
    core->simulator = new PistonEngineSimulator;
    PistonEngineSimulator *sim = core->simulator;
    Simulator::Parameters simulatorParams;
    simulatorParams.systemType = Simulator::SystemType::NsvOptimized;
    sim->initialize(simulatorParams);
    sim->loadSimulation(engine, core->vehicle(), core->transmission());
    sim->setFluidSimulationSteps(8);

    sim->setSimulationFrequency(
        simulationFrequency > 0 ? simulationFrequency : (int)engine->getSimulationFrequency());

    Synthesizer::AudioParameters audio = sim->synthesizer().getAudioParameters();
    audio.inputSampleNoise = static_cast<float>(engine->getInitialJitter());
    audio.airNoise = static_cast<float>(engine->getInitialNoise());
    audio.dF_F_mix = static_cast<float>(engine->getInitialHighFrequencyGain());
    sim->synthesizer().setAudioParameters(audio);
    engine_sim_set_leveler_mode(core.get(), ENGINE_SIM_LEVELER_RPM_SCALED);

    std::vector<int16_t> samples;
    // The M177 shares the F136's muffled exhaust response (mild_exhaust_reverb).
    const uint8_t *irBytes = profile == ENGINE_SIM_PROFILE_LS_V8 ? kLsV8ImpulseResponseWav : kF136V8ImpulseResponseWav;
    const size_t irSize = profile == ENGINE_SIM_PROFILE_LS_V8 ? kLsV8ImpulseResponseWavSize : kF136V8ImpulseResponseWavSize;
    if (readWavPcm16Mono(irBytes, irSize, &samples)) {
        for (int i = 0; i < engine->getExhaustSystemCount(); ++i) {
            ImpulseResponse *response = engine->getExhaustSystem(i)->getImpulseResponse();
            sim->synthesizer().initializeImpulseResponse(
                samples.data(), (unsigned int)samples.size(), (float)response->getVolume(), i);
        }
    }

    sim->startAudioRenderingThread();
    return core.release();
    }
    catch (...) { return nullptr; }
}

EngineSimCore *engine_sim_create_ls_v8(int simulationFrequency) {
    return engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, simulationFrequency);
}

void engine_sim_destroy(EngineSimCore *core) {
    if (core == nullptr) return;

    if (core->simulator) {
        core->simulator->releaseSimulation();
        delete core->simulator;
    }
    if (core->profile == ENGINE_SIM_PROFILE_LS_V8) destroyLsV8(&core->ls);
    else if (core->profile == ENGINE_SIM_PROFILE_F136_V8) destroyF136V8(&core->f136);
    else destroyM177V8(&core->m177);
    delete core;
}

EngineSimProfile engine_sim_profile(const EngineSimCore *core) {
    return core ? core->profile : static_cast<EngineSimProfile>(-1);
}

double engine_sim_profile_min_rpm(EngineSimProfile profile) {
    (void)profile;
    return 0;
}

double engine_sim_profile_max_rpm(EngineSimProfile profile) {
    if (profile == ENGINE_SIM_PROFILE_LS_V8) return 8000;
    if (profile == ENGINE_SIM_PROFILE_F136_V8) return 9000;
    if (profile == ENGINE_SIM_PROFILE_M177_V8) return 7200;
    return 0;
}

namespace {
double redlineRpm(EngineSimProfile profile) {
    if (profile == ENGINE_SIM_PROFILE_LS_V8) return 6000;
    if (profile == ENGINE_SIM_PROFILE_F136_V8) return 8500;
    return 7000;
}

// RMS loudness the RPM-scaled leveler aims for. The raw signal is far louder at
// closed throttle than open, so a fixed partial-compression curve made the engine
// quieter as the throttle opened; an explicit target keeps loudness rising with
// both RPM and throttle on every engine.
float rpmScaledTarget(const EngineSimCore *core) {
    constexpr double fullScale = 9000;  // redline, wide open; peaks then sit just past the 20000 knee
    const double rpm = std::fabs(core->engine()->getRpm());
    const double speed = std::clamp(rpm / redlineRpm(core->profile), 0.1, 1.1);
    const double throttle = std::clamp(core->engine()->getSpeedControl(), 0.0, 1.0);
    return (float)(fullScale * std::pow(speed, 0.6) * (0.75 + 0.25 * throttle));
}

void updateLevelerTarget(EngineSimCore *core) {
    if (!core->rpmScaledLeveler) return;
    const float target = rpmScaledTarget(core);
    // Ease over a few frames so a throttle stab doesn't step the gain.
    core->levelerTarget = core->levelerTarget > 0
        ? core->levelerTarget + 0.3f * (target - core->levelerTarget)
        : target;
    Synthesizer &synth = core->simulator->synthesizer();
    Synthesizer::AudioParameters audio = synth.getAudioParameters();
    audio.levelerTarget = core->levelerTarget;
    synth.setAudioParameters(audio);
}
}

void engine_sim_set_leveler_mode(EngineSimCore *core, int mode) {
    if (!core) return;
    Synthesizer &synth = core->simulator->synthesizer();
    Synthesizer::AudioParameters audio = synth.getAudioParameters();
    if (mode == ENGINE_SIM_LEVELER_PEAK) {
        // Headroom: the leveler smooths its gain, so peaks overshoot the target and
        // clip at the stock 30000.
        audio.levelerRmsDetector = false;
        audio.levelerRatio = 1.0f;
        audio.levelerReference = 0.0f;
        audio.levelerTarget = 16000.0f;
        audio.levelerMaxGain = Synthesizer::AudioParameters().levelerMaxGain;
    }
    else {
        // Level by RMS rather than peak, so spiky firing pulses don't pull loudness
        // down, normalising fully to a target that follows RPM and throttle.
        audio.levelerRmsDetector = true;
        audio.levelerRatio = 1.0f;
        audio.levelerReference = 0.0f;
        audio.levelerMaxGain = 4.0f;  // weak raw signal at low RPM, wide open
        core->levelerTarget = 0;
        audio.levelerTarget = rpmScaledTarget(core);
    }
    core->rpmScaledLeveler = mode != ENGINE_SIM_LEVELER_PEAK;
    synth.setAudioParameters(audio);
}

void engine_sim_hold_rpm(EngineSimCore *core, double rpm) {
    engine_sim_set_ignition(core, true);
    engine_sim_set_throttle(core, 0.5);
    engine_sim_set_target_rpm(core, rpm);
}

void engine_sim_set_target_rpm(EngineSimCore *core, double rpm) {
    if (!core || !std::isfinite(rpm)) return;
    rpm = std::clamp(rpm, engine_sim_profile_min_rpm(core->profile), engine_sim_profile_max_rpm(core->profile));
    core->simulator->m_dyno.m_enabled = true;
    core->simulator->m_dyno.m_hold = true;
    core->simulator->m_dyno.m_rotationSpeed = units::rpm(rpm);
}

void engine_sim_set_throttle(EngineSimCore *core, double throttle) {
    if (core && std::isfinite(throttle)) core->engine()->setSpeedControl(std::clamp(throttle, 0.0, 1.0));
}

void engine_sim_set_ignition(EngineSimCore *core, int enabled) {
    if (!core) return;
    core->ignition = enabled != 0;
    core->engine()->getIgnitionModule()->m_enabled = core->ignition;
}

// The leveler adapts its gain slowly (and boosts quiet passages up to 1.9x), so a
// sudden loud firing pulse can overshoot into hard clipping, which is audible as
// a crack. This stateless soft knee bends such peaks smoothly below full scale.
static void softLimit(int16_t *samples, int count) {
    constexpr float knee = 20000.0f;
    constexpr float headroom = 12000.0f;
    for (int i = 0; i < count; ++i) {
        const float x = samples[i];
        const float magnitude = std::fabs(x);
        if (magnitude <= knee) continue;
        const float limited = knee + headroom * std::tanh((magnitude - knee) / headroom);
        samples[i] = (int16_t)std::copysign(limited, x);
    }
}

static int renderLoop(EngineSimCore *core, int16_t *out, int sampleCount, bool synchronous) {
    if (!core || !out || sampleCount <= 0) return 0;
    PistonEngineSimulator *sim = core->simulator;
    int written = 0;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(30 + sampleCount / ENGINE_SIM_SAMPLE_RATE * 10);

    while (written < sampleCount && std::chrono::steady_clock::now() < deadline) {
        // Unlike a live player, this loop is not paced by playback. Without a limit,
        // physics outruns the synthesizer and overflows its input ring buffer, which
        // overwrites unread input and is heard as periodic cracks. Hold physics back
        // while enough input is queued.
        if (sim->getSynthesizerInputLatency() < sim->getTargetSynthesizerLatency()) {
            updateLevelerTarget(core);
            sim->startFrame(kFrameSeconds);
            while (sim->simulateStep()) { /* void */ }
            sim->endFrame();
            if (synchronous) waitForRender(sim->synthesizer());
        }
        else {
            // The render thread only wakes after an input block ends.
            sim->endFrame();
        }

        const int got = sim->readAudioOutput(sampleCount - written, out + written);
        softLimit(out + written, got);
        written += got;
        if (got == 0) std::this_thread::sleep_for(std::chrono::microseconds(500));
    }

    if (!core->ignition) std::fill(out, out + written, 0);
    return written;
}

int engine_sim_render(EngineSimCore *core, int16_t *out, int sampleCount) {
    return renderLoop(core, out, sampleCount, false);
}

int engine_sim_render_synchronous(EngineSimCore *core, int16_t *out, int sampleCount) {
    return renderLoop(core, out, sampleCount, true);
}

double engine_sim_rpm(const EngineSimCore *core) {
    return core ? core->engine()->getRpm() : 0;
}

int engine_sim_simulation_frequency(const EngineSimCore *core) {
    return core ? core->simulator->getSimulationFrequency() : 0;
}
