/* Mojara v0.10.2 opt-in, process-local request instrumentation.
 * No heap allocations or locks on the request path. Thread-safe counters.
 * HTTP handler/service time, not TCP accept, request body read or wire time.
 */
#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

static _Atomic uint64_t total = 0;
static _Atomic uint64_t active = 0;
static _Atomic uint64_t peak = 0;
static _Atomic uint64_t elapsed_ns = 0;
static _Atomic uint64_t failures = 0;
static _Atomic uint64_t status_4xx = 0;
static _Atomic uint64_t status_5xx = 0;
/* Operator-driven readiness transition. Does not stop TCP accept or flush
 * Flare's connection queues: safe removal from a load balancer comes first. */
static _Atomic bool draining = false;

int mj_runtime_begin_drain(void) {
    atomic_store_explicit(&draining, true, memory_order_release);
    return 1;
}

int mj_runtime_is_draining(void) {
    return atomic_load_explicit(&draining, memory_order_acquire) ? 1 : 0;
}

uint64_t mj_runtime_in_flight(void) {
    return atomic_load_explicit(&active, memory_order_acquire);
}

/* Inclusive thresholds: 100us, 250us, 500us, 1ms, 5ms, 10ms, 50ms, >50ms */
static const uint64_t bounds_ns[7] = {100000, 250000, 500000, 1000000,
                                      5000000, 10000000, 50000000};
static _Atomic uint64_t histogram[8];

static uint64_t monotonic_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * UINT64_C(1000000000) + (uint64_t)ts.tv_nsec;
}

uint64_t mj_metrics_start(void) {
    uint64_t start = monotonic_ns();
    uint64_t current = atomic_fetch_add_explicit(&active, 1, memory_order_relaxed) + 1;
    uint64_t previous = atomic_load_explicit(&peak, memory_order_relaxed);
    while (current > previous && !atomic_compare_exchange_weak_explicit(
        &peak, &previous, current, memory_order_relaxed, memory_order_relaxed)) {}
    return start;
}

void mj_metrics_finish(uint64_t started_ns, int status) {
    uint64_t now = monotonic_ns();
    uint64_t elapsed = (started_ns != 0 && now >= started_ns) ? now - started_ns : 0;
    unsigned bucket = 7;
    for (unsigned i = 0; i < 7; ++i) {
        if (elapsed <= bounds_ns[i]) { bucket = i; break; }
    }
    atomic_fetch_add_explicit(&histogram[bucket], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&elapsed_ns, elapsed, memory_order_relaxed);
    atomic_fetch_add_explicit(&total, 1, memory_order_relaxed);
    if (status >= 400 && status < 500)
        atomic_fetch_add_explicit(&status_4xx, 1, memory_order_relaxed);
    if (status >= 500)
        atomic_fetch_add_explicit(&status_5xx, 1, memory_order_relaxed);
    if (status < 100 || status >= 500)
        atomic_fetch_add_explicit(&failures, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&active, 1, memory_order_relaxed);
}

/* Thread-local snapshot is stable until this thread calls again.
 * Snapshot counters are independently atomic, not an instantaneous transaction.
 * Caller must copy bytes into owned memory before yielding to another thread.
 */
const char *mj_metrics_snapshot_json(void) {
    static _Thread_local char buffer[1024];
    uint64_t h[8];
    for (int i = 0; i < 8; ++i) h[i] = atomic_load_explicit(&histogram[i], memory_order_relaxed);
    int n = snprintf(buffer, sizeof(buffer),
        "{\"scope\":\"process_handler\",\"total\":%" PRIu64
        ",\"in_flight\":%" PRIu64 ",\"peak_in_flight\":%" PRIu64
        ",\"failed\":%" PRIu64 ",\"status_4xx\":%" PRIu64
        ",\"status_5xx\":%" PRIu64 ",\"sum_latency_ns\":%" PRIu64
        ",\"latency_buckets_ns\":[%" PRIu64 ",%" PRIu64 ",%" PRIu64
        ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 ",%" PRIu64 "]}",
        atomic_load_explicit(&total, memory_order_relaxed),
        atomic_load_explicit(&active, memory_order_relaxed),
        atomic_load_explicit(&peak, memory_order_relaxed),
        atomic_load_explicit(&failures, memory_order_relaxed),
        atomic_load_explicit(&status_4xx, memory_order_relaxed),
        atomic_load_explicit(&status_5xx, memory_order_relaxed),
        atomic_load_explicit(&elapsed_ns, memory_order_relaxed),
        h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]);
    return (n >= 0 && (size_t)n < sizeof(buffer)) ? buffer : NULL;
}

/* Test-only building block, used exclusively by an opt-in, token-protected
 * loopback route. Sleeps on a handler thread to exercise coordinated shutdown.
 * Never invoked on a production request path without test mode enabled. */
int mj_runtime_test_pause_ms(int milliseconds) {
    if (milliseconds < 1 || milliseconds > 3000) return 0;
    struct timespec left = { milliseconds / 1000,
                             (long)(milliseconds % 1000) * 1000000L };
    while (nanosleep(&left, &left) == -1) {
        if (errno != EINTR) return 0;
    }
    return 1;
}
