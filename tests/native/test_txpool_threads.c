#include "../../source/native/txpool/txpool.h"
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

typedef struct { MJDBPool *pool; uint64_t token; int result; } Probe;
static void *probe_wrong_owner(void *arg) {
  Probe *p = arg;
  p->result = mjdb_begin(p->pool, p->token);
  return NULL;
}
static void *probe_timeout(void *arg) {
  Probe *p = arg;
  uint64_t token;
  p->result = mjdb_acquire(p->pool, 40, &token);
  return NULL;
}
int main(void) {
  MJDBPool *pool = mjdb_new_test(1);
  assert(pool != NULL);
  uint64_t token = 0;
  assert(mjdb_acquire(pool, 0, &token) == MJDB_OK);
  assert(token != 0);
  assert(mjdb_active_leases(pool) == 1);
  assert(mjdb_close(pool) == MJDB_BUSY);
  assert(mjdb_begin(pool, token) == MJDB_OK);
  assert(mjdb_begin(pool, token) == MJDB_ALREADY_IN_TRANSACTION);
  Probe p = {.pool=pool, .token=token, .result=999};
  pthread_t tid;
  assert(pthread_create(&tid, NULL, probe_wrong_owner, &p) == 0);
  pthread_join(tid, NULL);
  assert(p.result == MJDB_WRONG_THREAD);
  assert(pthread_create(&tid, NULL, probe_timeout, &p) == 0);
  pthread_join(tid, NULL);
  assert(p.result == MJDB_TIMEOUT);
  assert(mjdb_rollback(pool, token) == MJDB_OK);
  assert(mjdb_commit(pool, token) == MJDB_NOT_IN_TRANSACTION);
  assert(mjdb_begin(pool, token) == MJDB_OK);
  assert(mjdb_release(pool, token) == MJDB_OK); /* auto rollback */
  assert(mjdb_active_leases(pool) == 0);
  assert(mjdb_release(pool, token) == MJDB_INVALID); /* stale token */
  uint64_t second = 0;
  assert(mjdb_acquire(pool, 0, &second) == MJDB_OK);
  assert(second != token);
  assert(mjdb_release(pool, second) == MJDB_OK);
  assert(mjdb_close(pool) == MJDB_OK);
  puts("Mojara txpool lease, ownership, timeout and rollback tests passed.");
  return 0;
}

[executed on device: vmi3166522 (9dedaf3d-f67d-45f3-879f-08d518d2f7ef)