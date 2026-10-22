#ifndef ENGINE_SOUND_RING_H
#define ENGINE_SOUND_RING_H

#include <stddef.h>
#include <stdint.h>

typedef struct EngineSoundRing EngineSoundRing;

EngineSoundRing *engine_sound_ring_create(size_t capacity);
void engine_sound_ring_destroy(EngineSoundRing *ring);
size_t engine_sound_ring_write(EngineSoundRing *ring, const int16_t *samples, size_t count);
size_t engine_sound_ring_read(EngineSoundRing *ring, int16_t *samples, size_t count);
size_t engine_sound_ring_available(const EngineSoundRing *ring);
size_t engine_sound_ring_capacity(const EngineSoundRing *ring);
size_t engine_sound_ring_underruns(const EngineSoundRing *ring);

#endif
