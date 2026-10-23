// Built against the Release core: assert(false) must not be the only guard.
#include "ls_v8_builder.h"
#include "engine.h"
#include <cmath>
#include <cstdio>
#include <limits>

int main() {
    LsV8 ls;
    buildLsV8(&ls);
    auto chamber = ls.engine->getChamber(0);
    chamber->getPiston()->m_body.index = 0;
    atg_scs::LineConstraint constraint;
    constraint.F_x[0][0] = constraint.F_y[0][0] = 0;
    chamber->getPiston()->setCylinderConstraint(&constraint);
    atg_scs::SystemState state;
    state.resize(1, 0);
    state.v_x[0] = state.v_y[0] = 0;
    state.theta[0] = state.p_x[0] = state.p_y[0] = 0;
    state.f_x[0] = 17;
    state.f_y[0] = 23;
    state.t[0] = 0;
    for (double bad : {std::numeric_limits<double>::quiet_NaN(),
                       std::numeric_limits<double>::infinity(),
                       -std::numeric_limits<double>::infinity()}) {
        chamber->m_system.initialize(101325, 0.001, 300);
        chamber->m_system.changeEnergy(bad);
        chamber->apply(&state);
        if (state.f_x[0] != 17 || state.f_y[0] != 23 || state.t[0] != 0) {
            std::fprintf(stderr, "Invalid chamber force reached the solver\n");
            return 1;
        }
    }
    for (double bad : {std::numeric_limits<double>::quiet_NaN(),
                       std::numeric_limits<double>::infinity(),
                       -std::numeric_limits<double>::infinity()}) {
        chamber->m_system.initialize(101325, 0.001, 300);
        chamber->m_frictionModel.viscousFrictionCoefficient = bad;
        chamber->apply(&state);
        if (state.f_x[0] != 17 || state.f_y[0] != 23 || state.t[0] != 0) return 2;
        chamber->m_frictionModel.viscousFrictionCoefficient = 20;
        state.v_x[0] = bad;
        chamber->apply(&state);
        if (state.f_x[0] != 17 || state.f_y[0] != 23 || state.t[0] != 0) return 3;
        state.v_x[0] = 0;
    }
    chamber->m_system.initialize(202650, 0.001, 300);
    chamber->apply(&state);
    if (!std::isfinite(state.f_x[0]) || !std::isfinite(state.f_y[0])
        || (state.f_x[0] == 17 && state.f_y[0] == 23)) return 4;
    state.destroy();
    destroyLsV8(&ls);
    std::puts("Release NaN/+Inf/-Inf chamber force guard passed");
}
