/* Run as local standalone C regression, not shipped in production process. */
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern uint64_t mj_metrics_start(void);
extern void mj_metrics_finish(uint64_t, int);
extern const char *mj_metrics_snapshot_json(void);
extern int mj_runtime_begin_drain(void);
extern int mj_runtime_is_draining(void);
extern uint64_t mj_runtime_in_flight(void);
#define THREADS 8
#define ITERATIONS 15000
static void *worker(void *arg) {
    (void)arg;
    for (int i = 0; i < ITERATIONS; i++) {
        uint64_t started = mj_metrics_start();
        mj_metrics_finish(started, (i % 10 == 0) ? 503 : 200);
    }
    return NULL;
}
int main(void) {
    pthread_t threads[THREADS];
    for (int i = 0; i < THREADS; i++) assert(pthread_create(&threads[i], NULL, worker, NULL) == 0);
    for (int i = 0; i < THREADS; i++) assert(pthread_join(threads[i], NULL) == 0);
    assert(mj_runtime_in_flight() == 0);
    assert(mj_runtime_is_draining() == 0);
    assert(mj_runtime_begin_drain() == 1);
    assert(mj_runtime_is_draining() == 1);
    const char *json = mj_metrics_snapshot_json();
    assert(json != NULL);
    char expected[80];
    snprintf(expected, sizeof(expected), "\"total\":%d", THREADS * ITERATIONS);
    assert(strstr(json, expected) != NULL);
    assert(strstr(json, "\"in_flight\":0") != NULL);
    snprintf(expected, sizeof(expected), "\"status_5xx\":%d", THREADS * ITERATIONS / 10);
    assert(strstr(json, expected) != NULL);
    printf("Native Mojara concurrent telemetry test passed: %s\n", json);
}
