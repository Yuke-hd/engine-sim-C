#ifndef ENGINE_SIM_CORE_F136_V8_BUILDER_H
#define ENGINE_SIM_CORE_F136_V8_BUILDER_H

#include <memory>
#include <vector>

class Engine;
class Vehicle;
class Transmission;
class Function;
class Camshaft;
class Valvetrain;
class ImpulseResponse;
class Simulator;

// Hand port of engine-sim assets/engines/atg-video-2/08_ferrari_f136_v8.mr (the Piranha
// scripting layer is not vendored). Owns everything the script nodes would
// have heap-allocated beyond the Engine itself.
struct F136V8 {
    Engine *engine = nullptr;
    Vehicle *vehicle = nullptr;
    Transmission *transmission = nullptr;
    std::vector<Function *> functions;
    std::vector<Camshaft *> camshafts;
    std::vector<Valvetrain *> valvetrains;
    std::vector<ImpulseResponse *> impulseResponses;
};

void buildF136V8(F136V8 *f136);
void destroyF136V8(F136V8 *f136);

#endif
