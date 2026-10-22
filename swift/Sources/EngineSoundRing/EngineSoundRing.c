#include "EngineSoundRing.h"
#include <stdatomic.h>
#include <stdlib.h>

struct EngineSoundRing {
    size_t capacity;
    int16_t *samples;
    _Atomic size_t readIndex;
    _Atomic size_t writeIndex;
    _Atomic size_t underruns;
};

EngineSoundRing *engine_sound_ring_create(size_t capacity) {
    if (capacity == 0 || capacity > SIZE_MAX / sizeof(int16_t)) return NULL;
    EngineSoundRing *ring = calloc(1, sizeof(*ring));
    if (!ring) return NULL;
    ring->samples = calloc(capacity, sizeof(int16_t));
    if (!ring->samples) { free(ring); return NULL; }
    ring->capacity = capacity;
    return ring;
}

void engine_sound_ring_destroy(EngineSoundRing *ring) {
    if (!ring) return;
    free(ring->samples);
    free(ring);
}

size_t engine_sound_ring_write(EngineSoundRing *ring, const int16_t *samples, size_t count) {
    size_t write = atomic_load_explicit(&ring->writeIndex, memory_order_relaxed);
    size_t read = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    size_t space = ring->capacity - (write - read);
    if (count > space) count = space;
    for (size_t i = 0; i < count; ++i) ring->samples[(write + i) % ring->capacity] = samples[i];
    atomic_store_explicit(&ring->writeIndex, write + count, memory_order_release);
    return count;
}

size_t engine_sound_ring_read(EngineSoundRing *ring, int16_t *samples, size_t count) {
    size_t requested = count;
    size_t read = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    size_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    size_t available = write - read;
    if (count > available) count = available;
    for (size_t i = 0; i < count; ++i) samples[i] = ring->samples[(read + i) % ring->capacity];
    atomic_store_explicit(&ring->readIndex, read + count, memory_order_release);
    if (count < requested) atomic_fetch_add_explicit(&ring->underruns, requested - count, memory_order_relaxed);
    return count;
}

size_t engine_sound_ring_available(const EngineSoundRing *ring) {
    size_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    size_t read = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    return write - read;
}

size_t engine_sound_ring_capacity(const EngineSoundRing *ring) { return ring->capacity; }
size_t engine_sound_ring_underruns(const EngineSoundRing *ring) {
    return atomic_load_explicit(&ring->underruns, memory_order_relaxed);
}
