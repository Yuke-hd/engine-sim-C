#ifndef ENGINE_SIM_CORE_M177_V8_BUILDER_H
#define ENGINE_SIM_CORE_M177_V8_BUILDER_H

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

// Mercedes-AMG M177 4.0 L twin-turbo V8, modelled from published specs (there is
// no upstream engine-sim script for it). Owns everything beyond the Engine itself.
struct M177V8 {
    Engine *engine = nullptr;
    Vehicle *vehicle = nullptr;
    Transmission *transmission = nullptr;
    std::vector<Function *> functions;
    std::vector<Camshaft *> camshafts;
    std::vector<Valvetrain *> valvetrains;
    std::vector<ImpulseResponse *> impulseResponses;
};

void buildM177V8(M177V8 *m177);
void destroyM177V8(M177V8 *m177);

#endif
