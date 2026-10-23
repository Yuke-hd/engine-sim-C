#include "EngineSimCore.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

constexpr int sampleRate = 44100;

// Match the signed iPhone benchmark's warm-up and timed render sizes. These host
// measurements diagnose relative changes; they do not satisfy physical gates.
int main(int argc, char **argv) {
    if (argc < 2) return 1;
    for (int profile = 0; profile < 2; ++profile) {
        auto core = engine_sim_create(static_cast<EngineSimProfile>(profile), 0);
        if (!core) return 2;
        engine_sim_hold_rpm(core, 3000);
        std::vector<int16_t> samples(sampleRate * 3);
        if (engine_sim_render(core, samples.data(), sampleRate / 2) != sampleRate / 2
            || engine_sim_render(core, samples.data(), samples.size()) != samples.size()) return 3;
        double ratios[5];
        for (int run = 0; run < 5; ++run) {
            const auto start = std::chrono::steady_clock::now();
            const int count = engine_sim_render(core, samples.data(), samples.size());
            ratios[run] = std::chrono::duration<double>(
                std::chrono::steady_clock::now() - start).count() / 3;
            if (count != samples.size()) return 3;
        }
        std::sort(ratios, ratios + 5);
        std::printf("profile=%d freq=%d rpm=%.2f min=%.6f median=%.6f max=%.6f\n",
                    profile, engine_sim_simulation_frequency(core), engine_sim_rpm(core),
                    ratios[0], ratios[2], ratios[4]);
        std::fflush(stdout);
        engine_sim_destroy(core);
    }
    if (argc > 2) return 0;
    for (int profile = 0; profile < 2; ++profile) {
        for (int rpm : {1500, 3000, 5000}) {
            for (double throttle : {0., 0.5, 1.}) {
                std::srand(1);
                auto core = engine_sim_create(static_cast<EngineSimProfile>(profile), 0);
                if (!core) return 2;
                engine_sim_set_target_rpm(core, rpm);
                engine_sim_set_throttle(core, throttle);
                engine_sim_set_ignition(core, 1);
                std::vector<int16_t> samples(sampleRate * 2);
                if (engine_sim_render(core, samples.data(), samples.size()) != samples.size()
                    || engine_sim_render(core, samples.data(), samples.size()) != samples.size()) return 4;
                const auto path = std::string(argv[1]) + "-" + std::to_string(profile)
                    + "-" + std::to_string(rpm) + "-" + std::to_string(throttle) + ".pcm";
                auto file = std::fopen(path.c_str(), "wb");
                if (!file) return 5;
                const auto written = std::fwrite(samples.data(), sizeof(int16_t), samples.size(), file);
                std::fclose(file);
                if (written != samples.size()) return 6;
                std::printf("output %s rpm=%.2f\n", path.c_str(), engine_sim_rpm(core));
                engine_sim_destroy(core);
            }
        }
    }
}
