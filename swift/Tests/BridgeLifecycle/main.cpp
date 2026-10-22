#include "EngineSimCore.h"
#include <stdlib.h>
int main(void) {
    for (int i = 0; i < 40; ++i) {
        EngineSimCore *sim = engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0);
        if (!sim) return 1;
        engine_sim_set_target_rpm(sim, 3000);
        engine_sim_set_throttle(sim, 0.5);
        engine_sim_set_ignition(sim, 1);
        int16_t samples[882];
        if (engine_sim_render(sim, samples, 882) != 882) return 2;
        engine_sim_destroy(sim);
    }
    return 0;
}
