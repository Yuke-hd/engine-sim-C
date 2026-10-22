// Reproduce OS thread exhaustion deterministically without exhausting the host.
// A standalone process safely interposes pthread_create for std::thread.
#include "EngineSimCore.h"
#include <pthread.h>
#include <errno.h>
#include <stdio.h>
extern "C" int pthread_create(pthread_t*, const pthread_attr_t*, void*(*)(void*), void*) { return EAGAIN; }
int main() {
  auto *core = engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0);
  printf("thread-start failure returned %p (expected null)\n", (void*)core);
  if (core) { engine_sim_destroy(core); return 2; }
  return 0;
}
