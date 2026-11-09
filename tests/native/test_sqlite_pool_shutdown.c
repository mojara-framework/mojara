#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <pthread.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

void *mj_sp_open(const char *, int, int);
int mj_sp_stats_extended(void *, int *, int *, int *, int *, int *,
                         uint64_t *, uint64_t *, uint64_t *);
int mj_sp_begin_shutdown(void *);
void mj_sp_close(void *);
int mj_sp_query_one_text(void *, const char *, const char *, char *, int);
int mj_sp_test_hold(void *, int);

typedef struct { void *pool; int result; } Hold;
static void *hold_worker(void *arg) {
    Hold *h = (Hold *)arg;
    h->result = mj_sp_test_hold(h->pool, 280);
    return NULL;
}
static uint64_t now_ms(void) {
    struct timespec t;
    assert(clock_gettime(CLOCK_MONOTONIC, &t) == 0);
    return (uint64_t)t.tv_sec * 1000 + (uint64_t)t.tv_nsec / 1000000;
}

int main(void) {
    char dbpath[] = "/tmp/mojara-close-XXXXXX";
    int fd = mkstemp(dbpath);
    assert(fd >= 0);
    close(fd);
    sqlite3 *db = NULL;
    assert(sqlite3_open(dbpath, &db) == SQLITE_OK);
    assert(sqlite3_exec(db, "CREATE TABLE t (id INTEGER); INSERT INTO t VALUES(1)",
                        NULL, NULL, NULL) == SQLITE_OK);
    sqlite3_close(db);
    void *pool = mj_sp_open(dbpath, 1, 1000);
    assert(pool);
    Hold job = { pool, 0 };
    pthread_t thread;
    assert(pthread_create(&thread, NULL, hold_worker, &job) == 0);
    int capacity=0, active=0, waiting=0, peak=0, closing=0;
    uint64_t queries=0, waits=0, timeouts=0;
    bool seen_active = false;
    struct timespec tick = {0, 1000000};
    for (int i = 0; i < 500; ++i) {
        assert(mj_sp_stats_extended(pool, &capacity, &active, &waiting, &peak,
                                    &closing, &queries, &waits, &timeouts) == 1);
        if (active == 1) { seen_active = true; break; }
        nanosleep(&tick, NULL);
    }
    assert(seen_active);
    assert(mj_sp_begin_shutdown(pool) == 1);
    char result[16];
    assert(mj_sp_query_one_text(pool, "SELECT id FROM t WHERE id=?", "1", result, 16) == -5);
    uint64_t started = now_ms();
    mj_sp_close(pool); /* Must wait until the occupied lease returns. */
    uint64_t elapsed = now_ms() - started;
    assert(pthread_join(thread, NULL) == 0);
    assert(job.result == 1);
    assert(elapsed >= 60); /* The active lease must not be closed immediately. */
    unlink(dbpath);
    printf("PASS: SQLite pool shutdown waited %llu ms for active lease\n",
           (unsigned long long)elapsed);
    return 0;
}
